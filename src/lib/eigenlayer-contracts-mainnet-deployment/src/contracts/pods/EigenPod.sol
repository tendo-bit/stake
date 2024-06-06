// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.12;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/AddressUpgradeable.sol";

import "../libraries/BeaconChainProofs.sol";
import "../libraries/BytesLib.sol";
import "../libraries/Endian.sol";

import "../interfaces/IETHPOSDeposit.sol";
import "../interfaces/IEigenPodManager.sol";
import "../interfaces/IEigenPod.sol";
import "../interfaces/IDelayedWithdrawalRouter.sol";
import "../interfaces/IPausable.sol";

import "./EigenPodPausingConstants.sol";

/**
 * @title The implementation contract used for restaking beacon chain ETH on EigenLayer 
 * @author Layr Labs, Inc.
 * @notice Terms of Service: https://docs.eigenlayer.xyz/overview/terms-of-service
 * @notice The main functionalities are:
 * - creating new ETH validators with their withdrawal credentials pointed to this contract
 * - proving from beacon chain state roots that withdrawal credentials are pointed to this contract
 * - proving from beacon chain state roots the balances of ETH validators with their withdrawal credentials
 *   pointed to this contract
 * - updating aggregate balances in the EigenPodManager
 * - withdrawing eth when withdrawals are initiated
 * @dev Note that all beacon chain balances are stored as gwei within the beacon chain datastructures. We choose
 *   to account balances in terms of gwei in the EigenPod contract and convert to wei when making calls to other contracts
 */
contract EigenPod is IEigenPod, Initializable, ReentrancyGuardUpgradeable, EigenPodPausingConstants {
    using BytesLib for bytes;

    // CONSTANTS + IMMUTABLES
    uint256 internal constant GWEI_TO_WEI = 1e9;

    /// @notice Maximum "staleness" of a Beacon Chain state root against which `verifyOvercommittedStake` may be proven. 7 days in blocks.
    uint256 internal constant VERIFY_OVERCOMMITTED_WINDOW_BLOCKS = 50400;

    /// @notice This is the beacon chain deposit contract
    IETHPOSDeposit public immutable ethPOS;

    /// @notice Contract used for withdrawal routing, to provide an extra "safety net" mechanism
    IDelayedWithdrawalRouter public immutable delayedWithdrawalRouter;

    /// @notice The single EigenPodManager for EigenLayer
    IEigenPodManager public immutable eigenPodManager;

    /// @notice The amount of eth, in gwei, that is restaked per validator
    uint64 public immutable REQUIRED_BALANCE_GWEI;

    /// @notice The amount of eth, in wei, that is restaked per ETH validator into EigenLayer
    uint256 public immutable REQUIRED_BALANCE_WEI;

    /// @notice The owner of this EigenPod
    address public podOwner;

    /**
     * @notice The latest block number at which the pod owner withdrew the balance of the pod.
     * @dev This variable is only updated when the `withdraw` function is called, which can only occur before `hasRestaked` is set to true for this pod.
     * Proofs for this pod are only valid against Beacon Chain state roots corresponding to blocks after the stored `mostRecentWithdrawalBlockNumber`.
     */
    uint64 public mostRecentWithdrawalBlockNumber;

    // STORAGE VARIABLES
    /// @notice the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from the Beacon Chain but not from EigenLayer), 
    uint64 public restakedExecutionLayerGwei;

    /// @notice an indicator of whether or not the podOwner has ever "fully restaked" by successfully calling `verifyCorrectWithdrawalCredentials`.
    bool public hasRestaked;

    /// @notice this is a mapping of validator indices to a Validator struct containing pertinent info about the validator
    mapping(uint40 => VALIDATOR_STATUS) public validatorStatus;

    /// @notice This is a mapping of validatorIndex to withdrawalIndex to whether or not they have proven a withdrawal for that index
    mapping(uint40 => mapping(uint64 => bool)) public provenPartialWithdrawal;

    /// @notice Emitted when an ETH validator stakes via this eigenPod
    event EigenPodStaked(bytes pubkey);

    /// @notice Emitted when an ETH validator's withdrawal credentials are successfully verified to be pointed to this eigenPod
    event ValidatorRestaked(uint40 validatorIndex);

    /// @notice Emitted when an ETH validator is proven to have a balance less than `REQUIRED_BALANCE_GWEI` in the beacon chain
    event ValidatorOvercommitted(uint40 validatorIndex);
    
    /// @notice Emitted when an ETH validator is prove to have withdrawn from the beacon chain
    event FullWithdrawalRedeemed(uint40 validatorIndex, address indexed recipient, uint64 withdrawalAmountGwei);

    /// @notice Emitted when a partial withdrawal claim is successfully redeemed
    event PartialWithdrawalRedeemed(uint40 validatorIndex, address indexed recipient, uint64 partialWithdrawalAmountGwei);

    /// @notice Emitted when restaked beacon chain ETH is withdrawn from the eigenPod.
    event RestakedBeaconChainETHWithdrawn(address indexed recipient, uint256 amount);

    modifier onlyEigenPodManager {
        require(msg.sender == address(eigenPodManager), "EigenPod.onlyEigenPodManager: not eigenPodManager");
        _;
    }

    modifier onlyEigenPodOwner {
        require(msg.sender == podOwner, "EigenPod.onlyEigenPodOwner: not podOwner");
        _;
    }

    modifier onlyNotFrozen {
        require(!eigenPodManager.slasher().isFrozen(podOwner), "EigenPod.onlyNotFrozen: pod owner is frozen");
        _;
    }

    modifier hasNeverRestaked {
        require(!hasRestaked, "EigenPod.hasNeverRestaked: restaking is enabled");
        _;
    }

    /// @notice Checks that `blockNumber` is strictly greater than the value stored in `mostRecentWithdrawalBlockNumber`
    modifier proofIsForValidBlockNumber(uint64 blockNumber) {
        require(blockNumber > mostRecentWithdrawalBlockNumber,
            "EigenPod.proofIsForValidBlockNumber: beacon chain proof must be for block number after mostRecentWithdrawalBlockNumber");
        _;
    }

    /**
     * @notice Based on 'Pausable' code, but uses the storage of the EigenPodManager instead of this contract. This construction
     * is necessary for enabling pausing all EigenPods at the same time (due to EigenPods being Beacon Proxies).
     * Modifier throws if the `indexed`th bit of `_paused` in the EigenPodManager is 1, i.e. if the `index`th pause switch is flipped.
     */
    modifier onlyWhenNotPaused(uint8 index) {
        require(!IPausable(address(eigenPodManager)).paused(index), "EigenPod.onlyWhenNotPaused: index is paused in EigenPodManager");
        _;
    }

    constructor(
        IETHPOSDeposit _ethPOS,
        IDelayedWithdrawalRouter _delayedWithdrawalRouter,
        IEigenPodManager _eigenPodManager,
        uint256 _REQUIRED_BALANCE_WEI
    ) {
        ethPOS = _ethPOS;
        delayedWithdrawalRouter = _delayedWithdrawalRouter;
        eigenPodManager = _eigenPodManager;
        REQUIRED_BALANCE_WEI = _REQUIRED_BALANCE_WEI;
        REQUIRED_BALANCE_GWEI = uint64(_REQUIRED_BALANCE_WEI / GWEI_TO_WEI);
        require(_REQUIRED_BALANCE_WEI % GWEI_TO_WEI == 0, "EigenPod.contructor: _REQUIRED_BALANCE_WEI is not a whole number of gwei");
        _disableInitializers();
    }

    /// @notice Used to initialize the pointers to addresses crucial to the pod's functionality. Called on construction by the EigenPodManager.
    function initialize(address _podOwner) external initializer {
        require(_podOwner != address(0), "EigenPod.initialize: podOwner cannot be zero address");
        podOwner = _podOwner;
    }

    /// @notice Called by EigenPodManager when the owner wants to create another ETH validator.
    function stake(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable onlyEigenPodManager {
        // stake on ethpos
        require(msg.value == 32 ether, "EigenPod.stake: must initially stake for any validator with 32 ether");
        ethPOS.deposit{value : 32 ether}(pubkey, _podWithdrawalCredentials(), signature, depositDataRoot);
        emit EigenPodStaked(pubkey);
    }

    /**
     * @notice  This function verifies that the withdrawal credentials of the podOwner are pointed to
     * this contract. It also verifies the current (not effective) balance  of the validator.  It verifies the provided proof of the ETH validator against the beacon chain state
     * root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.
     * @param oracleBlockNumber is the Beacon Chain blockNumber whose state root the `proof` will be proven against.
     * @param validatorIndex is the index of the validator being proven, refer to consensus specs 
     * @param proofs is the bytes that prove the ETH validator's balance and withdrawal credentials against a beacon chain state root
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs 
     * for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyWithdrawalCredentialsAndBalance(
        uint64 oracleBlockNumber,
        uint40 validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs calldata proofs,
        bytes32[] calldata validatorFields
    )
        external
        onlyWhenNotPaused(PAUSED_EIGENPODS_VERIFY_CREDENTIALS)
        // check that the provided `oracleBlockNumber` is after the `mostRecentWithdrawalBlockNumber`
        proofIsForValidBlockNumber(oracleBlockNumber)
    {
        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.INACTIVE,
            "EigenPod.verifyCorrectWithdrawalCredentials: Validator must be inactive to prove withdrawal credentials");

        require(validatorFields[BeaconChainProofs.VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX] == bytes32(_podWithdrawalCredentials()),
            "EigenPod.verifyCorrectWithdrawalCredentials: Proof is not for this EigenPod");
        // deserialize the balance field from the balanceRoot
        uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(validatorIndex, proofs.balanceRoot);
        
        // make sure the balance is greater than the amount restaked per validator
        require(validatorCurrentBalanceGwei >= REQUIRED_BALANCE_GWEI,
            "EigenPod.verifyCorrectWithdrawalCredentials: ETH validator's balance must be greater than or equal to the restaked balance per validator");

        // verify ETH validator proof
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot(oracleBlockNumber);
        BeaconChainProofs.verifyValidatorFields(
            validatorIndex,
            beaconStateRoot,
            proofs.validatorFieldsProof,
            validatorFields
        );

        // verify ETH validator's current balance, which is stored in the `balances` container of the beacon state
        BeaconChainProofs.verifyValidatorBalance(
            validatorIndex,
            beaconStateRoot,
            proofs.validatorBalanceProof,
            proofs.balanceRoot
        );
        // set the status to active
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.ACTIVE;

        // Sets "hasRestaked" to true if it hasn't been set yet. 
        if (!hasRestaked) {
            hasRestaked = true;
        }

        emit ValidatorRestaked(validatorIndex);

        // virtually deposit REQUIRED_BALANCE_WEI for new ETH validator
        eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records an overcommitment of stake to EigenLayer on behalf of a certain ETH validator.
     *         If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
     *         The ETH validator's shares in the enshrined beaconChainETH strategy are also removed from the StrategyManager and undelegated.
     * @param oracleBlockNumber The oracleBlockNumber whose state root the `proof` will be proven against.
     *        Must be within `VERIFY_OVERCOMMITTED_WINDOW_BLOCKS` of the current block.
     * @param validatorIndex is the index of the validator being proven, refer to consensus specs 
     * @param proofs is the proof of the validator's balance and validatorFields in the balance tree and the balanceRoot to prove for
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *                                    the StrategyManager in case it must be removed from the list of the podOwner's strategies
     * @param validatorFields are the fields of the "Validator Container", refer to consensus specs
     * @dev For more details on the Beacon Chain spec, see: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
     */
    function verifyOvercommittedStake(
        uint40 validatorIndex,
        BeaconChainProofs.ValidatorFieldsAndBalanceProofs calldata proofs,
        bytes32[] calldata validatorFields,
        uint256 beaconChainETHStrategyIndex,
        uint64 oracleBlockNumber
    ) external onlyWhenNotPaused(PAUSED_EIGENPODS_VERIFY_OVERCOMMITTED) {
       // ensure that the blockNumber being proven against is not "too stale", i.e. that the validator was *recently* overcommitted.
        require(oracleBlockNumber + VERIFY_OVERCOMMITTED_WINDOW_BLOCKS >= block.number,
            "EigenPod.verifyOvercommittedStake: specified blockNumber is too far in past");

        require(validatorStatus[validatorIndex] == VALIDATOR_STATUS.ACTIVE, "EigenPod.verifyOvercommittedStake: Validator not active");

        // deserialize the balance field from the balanceRoot
        uint64 validatorCurrentBalanceGwei = BeaconChainProofs.getBalanceFromBalanceRoot(validatorIndex, proofs.balanceRoot);        

        require(validatorCurrentBalanceGwei < REQUIRED_BALANCE_GWEI,
            "EigenPod.verifyOvercommittedStake: validator's balance must be less than the restaked balance per validator");
        
        // verify ETH validator proof
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot(oracleBlockNumber);
 
        /**
         * If validator's balance is zero, then either they have fully withdrawn or they have been slashed down zero.
         * If the validator *has* been slashed, then this function can proceed. If they have *not* been slashed, then
         * the `verifyAndProcessWithdrawal` function should be called instead.
         */
        if (validatorCurrentBalanceGwei == 0) {
            uint64 slashedStatus = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_SLASHED_INDEX]);
            require(slashedStatus == 1, "EigenPod.verifyOvercommittedStake: Validator must be slashed to be overcommitted");
            //Verify the validator fields, which contain the validator's slashed status
            BeaconChainProofs.verifyValidatorFields(
                validatorIndex,
                beaconStateRoot,
                proofs.validatorFieldsProof,
                validatorFields
            );
        }
        // verify ETH validator's current balance, which is stored in the `balances` container of the beacon state
       BeaconChainProofs.verifyValidatorBalance(
            validatorIndex,
            beaconStateRoot,
            proofs.validatorBalanceProof,
            proofs.balanceRoot
        );

        // mark the ETH validator as overcommitted
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.OVERCOMMITTED;

        emit ValidatorOvercommitted(validatorIndex);

        // remove and undelegate shares in EigenLayer
        eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, REQUIRED_BALANCE_WEI);
    }

    /**
     * @notice This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod
     * @param withdrawalProofs is the information needed to check the veracity of the block number and withdrawal being proven
     * @param validatorFieldsProof is the information needed to check the veracity of the validator fields being proven
     * @param withdrawalFields are the fields of the withdrawal being proven
     * @param validatorFields are the fields of the validator being proven
     * @param beaconChainETHStrategyIndex is the index of the beaconChainETHStrategy for the pod owner for the callback to 
     *        the EigenPodManager to the StrategyManager in case it must be removed from the podOwner's list of strategies
     * @param oracleBlockNumber is the Beacon Chain blockNumber whose state root the `proof` will be proven against.
     */
    function verifyAndProcessWithdrawal(
        BeaconChainProofs.WithdrawalProofs calldata withdrawalProofs, 
        bytes calldata validatorFieldsProof,
        bytes32[] calldata validatorFields,
        bytes32[] calldata withdrawalFields,
        uint256 beaconChainETHStrategyIndex,
        uint64 oracleBlockNumber
    )
        external
        onlyWhenNotPaused(PAUSED_EIGENPODS_VERIFY_WITHDRAWAL)
        onlyNotFrozen
        /** 
         * Check that the provided block number being proven against is after the `mostRecentWithdrawalBlockNumber`.
         * Without this check, there is an edge case where a user proves a past withdrawal for a validator whose funds they already withdrew,
         * as a way to "withdraw the same funds twice" without providing adequate proof.
         * Note that this check is not made using the oracleBlockNumber as in the `verifyWithdrawalCredentials` proof; instead this proof
         * proof is made for the block number of the withdrawal, which may be within 8192 slots of the oracleBlockNumber. 
         * This difference in modifier usage is OK, since it is still not possible to `verifyAndProcessWithdrawal` against a slot that occurred
         * *prior* to the proof provided in the `verifyWithdrawalCredentials` function.
         */
        proofIsForValidBlockNumber(Endian.fromLittleEndianUint64(withdrawalProofs.blockNumberRoot))
    {
        /**
         * If the validator status is inactive, then withdrawal credentials were never verified for the validator,
         * and thus we cannot know that the validator is related to this EigenPod at all!
         */
        uint40 validatorIndex = uint40(Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_INDEX_INDEX]));
        
        require(validatorStatus[validatorIndex] != VALIDATOR_STATUS.INACTIVE,
            "EigenPod.verifyOvercommittedStake: Validator never proven to have withdrawal credentials pointed to this contract");

        // fetch the beacon state root for the specified block
        bytes32 beaconStateRoot = eigenPodManager.getBeaconChainStateRoot(oracleBlockNumber);

        // Verifying the withdrawal as well as the slot
        BeaconChainProofs.verifyWithdrawalProofs(beaconStateRoot, withdrawalProofs, withdrawalFields);
        // Verifying the validator fields, specifically the withdrawable epoch
        BeaconChainProofs.verifyValidatorFields(validatorIndex, beaconStateRoot, validatorFieldsProof, validatorFields);

        uint64 withdrawalAmountGwei = Endian.fromLittleEndianUint64(withdrawalFields[BeaconChainProofs.WITHDRAWAL_VALIDATOR_AMOUNT_INDEX]);

        //check if the withdrawal occured after mostRecentWithdrawalBlockNumber
        uint64 slot = Endian.fromLittleEndianUint64(withdrawalProofs.slotRoot);

        /**
         * if the validator's withdrawable epoch is less than or equal to the slot's epoch, then the validator has fully withdrawn because
         * a full withdrawal is only processable after the withdrawable epoch has passed.
         */
        // reference: uint64 withdrawableEpoch = Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_WITHDRAWABLE_EPOCH_INDEX]);
        if (Endian.fromLittleEndianUint64(validatorFields[BeaconChainProofs.VALIDATOR_WITHDRAWABLE_EPOCH_INDEX]) <= slot/BeaconChainProofs.SLOTS_PER_EPOCH) {
            _processFullWithdrawal(withdrawalAmountGwei, validatorIndex, beaconChainETHStrategyIndex, podOwner, validatorStatus[validatorIndex]);
        } else {
            _processPartialWithdrawal(slot, withdrawalAmountGwei, validatorIndex, podOwner);
        }
    }

    function _processFullWithdrawal(
        uint64 withdrawalAmountGwei,
        uint40 validatorIndex,
        uint256 beaconChainETHStrategyIndex,
        address recipient,
        VALIDATOR_STATUS status
    ) internal {
        uint256 amountToSend;

        // if the validator has not previously been proven to be "overcommitted"
        if (status == VALIDATOR_STATUS.ACTIVE) {
            // if the withdrawal amount is greater than the REQUIRED_BALANCE_GWEI (i.e. the amount restaked on EigenLayer, per ETH validator)
            if (withdrawalAmountGwei >= REQUIRED_BALANCE_GWEI) {
                // then the excess is immediately withdrawable
                amountToSend = uint256(withdrawalAmountGwei - REQUIRED_BALANCE_GWEI) * uint256(GWEI_TO_WEI);
                // and the extra execution layer ETH in the contract is REQUIRED_BALANCE_GWEI, which must be withdrawn through EigenLayer's normal withdrawal process
                restakedExecutionLayerGwei += REQUIRED_BALANCE_GWEI;
            } else {
                // otherwise, just use the full withdrawal amount to continue to "back" the podOwner's remaining shares in EigenLayer (i.e. none is instantly withdrawable)
                restakedExecutionLayerGwei += withdrawalAmountGwei;
                // remove and undelegate 'extra' (i.e. "overcommitted") shares in EigenLayer
                eigenPodManager.recordOvercommittedBeaconChainETH(podOwner, beaconChainETHStrategyIndex, uint256(REQUIRED_BALANCE_GWEI - withdrawalAmountGwei) * GWEI_TO_WEI);
            }
        // if the validator *has* previously been proven to be "overcommitted"
        } else if (status == VALIDATOR_STATUS.OVERCOMMITTED) {
            // if the withdrawal amount is greater than the REQUIRED_BALANCE_GWEI (i.e. the amount restaked on EigenLayer, per ETH validator)
            if (withdrawalAmountGwei >= REQUIRED_BALANCE_GWEI) {
                // then the excess is immediately withdrawable
                amountToSend = uint256(withdrawalAmountGwei - REQUIRED_BALANCE_GWEI) * uint256(GWEI_TO_WEI);
                // and the extra execution layer ETH in the contract is REQUIRED_BALANCE_GWEI, which must be withdrawn through EigenLayer's normal withdrawal process
                restakedExecutionLayerGwei += REQUIRED_BALANCE_GWEI;
                /**
                 * since in `verifyOvercommittedStake` the podOwner's beaconChainETH shares are decremented by `REQUIRED_BALANCE_WEI`, we must reverse the process here,
                 * in order to allow the podOwner to complete their withdrawal through EigenLayer's normal withdrawal process
                 */
                eigenPodManager.restakeBeaconChainETH(podOwner, REQUIRED_BALANCE_WEI);
            } else {
                // otherwise, just use the full withdrawal amount to continue to "back" the podOwner's remaining shares in EigenLayer (i.e. none is instantly withdrawable)
                restakedExecutionLayerGwei += withdrawalAmountGwei;
                /**
                 * since in `verifyOvercommittedStake` the podOwner's beaconChainETH shares are decremented by `REQUIRED_BALANCE_WEI`, we must reverse the process here,
                 * in order to allow the podOwner to complete their withdrawal through EigenLayer's normal withdrawal process
                 */
                eigenPodManager.restakeBeaconChainETH(podOwner, uint256(withdrawalAmountGwei) * GWEI_TO_WEI);
            }
        // If the validator status is withdrawn, they have already processed their ETH withdrawal
        }  else {
            revert("EigenPod.verifyBeaconChainFullWithdrawal: VALIDATOR_STATUS is WITHDRAWN or invalid VALIDATOR_STATUS");
        }

        // set the ETH validator status to withdrawn
        validatorStatus[validatorIndex] = VALIDATOR_STATUS.WITHDRAWN;

        emit FullWithdrawalRedeemed(validatorIndex, recipient, withdrawalAmountGwei);

        // send ETH to the `recipient`, if applicable
        if (amountToSend != 0) {
            _sendETH(recipient, amountToSend);
        }
    }

    function _processPartialWithdrawal(uint64 withdrawalHappenedSlot, uint64 partialWithdrawalAmountGwei, uint40 validatorIndex, address recipient) internal {
        require(!provenPartialWithdrawal[validatorIndex][withdrawalHappenedSlot], "EigenPod._processPartialWithdrawal: partial withdrawal has already been proven for this slot");

        provenPartialWithdrawal[validatorIndex][withdrawalHappenedSlot] = true;
        emit PartialWithdrawalRedeemed(validatorIndex, recipient, partialWithdrawalAmountGwei);

        // send the ETH to the `recipient`
        _sendETH(recipient, uint256(partialWithdrawalAmountGwei) * uint256(GWEI_TO_WEI));
    }

    /**
     * @notice Transfers `amountWei` in ether from this contract to the specified `recipient` address
     * @notice Called by EigenPodManager to withdrawBeaconChainETH that has been added to the EigenPod's balance due to a withdrawal from the beacon chain.
     * @dev Called during withdrawal or slashing.
     */
    function withdrawRestakedBeaconChainETH(
        address recipient,
        uint256 amountWei
    )
        external
        onlyEigenPodManager
    {
        // reduce the restakedExecutionLayerGwei
        restakedExecutionLayerGwei -= uint64(amountWei / GWEI_TO_WEI);

        emit RestakedBeaconChainETHWithdrawn(recipient, amountWei);

        // transfer ETH from pod to `recipient`
        _sendETH(recipient, amountWei);
    }

    /// @notice Called by the pod owner to withdraw the balance of the pod when `hasRestaked` is set to false
    function withdrawBeforeRestaking() external onlyEigenPodOwner hasNeverRestaked {
        mostRecentWithdrawalBlockNumber = uint32(block.number);
        _sendETH(podOwner, address(this).balance);
    }

    // INTERNAL FUNCTIONS
    function _podWithdrawalCredentials() internal view returns(bytes memory) {
        return abi.encodePacked(bytes1(uint8(1)), bytes11(0), address(this));
    }

    function _sendETH(address recipient, uint256 amountWei) internal {
        delayedWithdrawalRouter.createDelayedWithdrawal{value: amountWei}(podOwner, recipient);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[46] private __gap;
}