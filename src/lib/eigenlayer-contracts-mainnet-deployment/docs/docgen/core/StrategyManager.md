# Solidity API

## StrategyManager

This contract is for managing deposits in different strategies. The main
functionalities are:
- adding and removing strategies that any delegator can deposit into
- enabling deposit of assets into specified strategy(s)
- enabling withdrawal of assets from specified strategy(s)
- recording deposit of ETH into settlement layer
- slashing of assets for permissioned strategies

### GWEI_TO_WEI

```solidity
uint256 GWEI_TO_WEI
```

### PAUSED_DEPOSITS

```solidity
uint8 PAUSED_DEPOSITS
```

### PAUSED_WITHDRAWALS

```solidity
uint8 PAUSED_WITHDRAWALS
```

### ORIGINAL_CHAIN_ID

```solidity
uint256 ORIGINAL_CHAIN_ID
```

### ERC1271_MAGICVALUE

```solidity
bytes4 ERC1271_MAGICVALUE
```

### Deposit

```solidity
event Deposit(address depositor, contract IERC20 token, contract IStrategy strategy, uint256 shares)
```

Emitted when a new deposit occurs on behalf of `depositor`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | Is the staker who is depositing funds into EigenLayer. |
| token | contract IERC20 | Is the token that `depositor` deposited. |
| strategy | contract IStrategy | Is the strategy that `depositor` has deposited into. |
| shares | uint256 | Is the number of new shares `depositor` has been granted in `strategy`. |

### ShareWithdrawalQueued

```solidity
event ShareWithdrawalQueued(address depositor, uint96 nonce, contract IStrategy strategy, uint256 shares)
```

Emitted when a new withdrawal occurs on behalf of `depositor`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | Is the staker who is queuing a withdrawal from EigenLayer. |
| nonce | uint96 | Is the withdrawal's unique identifier (to the depositor). |
| strategy | contract IStrategy | Is the strategy that `depositor` has queued to withdraw from. |
| shares | uint256 | Is the number of shares `depositor` has queued to withdraw. |

### WithdrawalQueued

```solidity
event WithdrawalQueued(address depositor, uint96 nonce, address withdrawer, address delegatedAddress, bytes32 withdrawalRoot)
```

Emitted when a new withdrawal is queued by `depositor`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | Is the staker who is withdrawing funds from EigenLayer. |
| nonce | uint96 | Is the withdrawal's unique identifier (to the depositor). |
| withdrawer | address | Is the party specified by `staker` who will be able to complete the queued withdrawal and receive the withdrawn funds. |
| delegatedAddress | address | Is the party who the `staker` was delegated to at the time of creating the queued withdrawal |
| withdrawalRoot | bytes32 | Is a hash of the input data for the withdrawal. |

### WithdrawalCompleted

```solidity
event WithdrawalCompleted(address depositor, uint96 nonce, address withdrawer, bytes32 withdrawalRoot)
```

Emitted when a queued withdrawal is completed

### StrategyWhitelisterChanged

```solidity
event StrategyWhitelisterChanged(address previousAddress, address newAddress)
```

Emitted when the `strategyWhitelister` is changed

### StrategyAddedToDepositWhitelist

```solidity
event StrategyAddedToDepositWhitelist(contract IStrategy strategy)
```

Emitted when a strategy is added to the approved list of strategies for deposit

### StrategyRemovedFromDepositWhitelist

```solidity
event StrategyRemovedFromDepositWhitelist(contract IStrategy strategy)
```

Emitted when a strategy is removed from the approved list of strategies for deposit

### WithdrawalDelayBlocksSet

```solidity
event WithdrawalDelayBlocksSet(uint256 previousValue, uint256 newValue)
```

Emitted when the `withdrawalDelayBlocks` variable is modified from `previousValue` to `newValue`.

### onlyNotFrozen

```solidity
modifier onlyNotFrozen(address staker)
```

### onlyFrozen

```solidity
modifier onlyFrozen(address staker)
```

### onlyEigenPodManager

```solidity
modifier onlyEigenPodManager()
```

### onlyStrategyWhitelister

```solidity
modifier onlyStrategyWhitelister()
```

### onlyStrategiesWhitelistedForDeposit

```solidity
modifier onlyStrategiesWhitelistedForDeposit(contract IStrategy strategy)
```

### constructor

```solidity
constructor(contract IDelegationManager _delegation, contract IEigenPodManager _eigenPodManager, contract ISlasher _slasher) public
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _delegation | contract IDelegationManager | The delegation contract of EigenLayer. |
| _eigenPodManager | contract IEigenPodManager | The contract that keeps track of EigenPod stakes for restaking beacon chain ether. |
| _slasher | contract ISlasher | The primary slashing contract of EigenLayer. |

### initialize

```solidity
function initialize(address initialOwner, address initialStrategyWhitelister, contract IPauserRegistry _pauserRegistry, uint256 initialPausedStatus, uint256 _withdrawalDelayBlocks) external
```

Initializes the strategy manager contract. Sets the `pauserRegistry` (currently **not** modifiable after being set),
and transfers contract ownership to the specified `initialOwner`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| initialOwner | address | Ownership of this contract is transferred to this address. |
| initialStrategyWhitelister | address | The initial value of `strategyWhitelister` to set. |
| _pauserRegistry | contract IPauserRegistry | Used for access control of pausing. |
| initialPausedStatus | uint256 | The initial value of `_paused` to set. |
| _withdrawalDelayBlocks | uint256 | The initial value of `withdrawalDelayBlocks` to set. |

### depositBeaconChainETH

```solidity
function depositBeaconChainETH(address staker, uint256 amount) external
```

Deposits `amount` of beaconchain ETH into this contract on behalf of `staker`

_Only callable by EigenPodManager._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| staker | address | is the entity that is restaking in eigenlayer, |
| amount | uint256 | is the amount of beaconchain ETH being restaked, |

### recordOvercommittedBeaconChainETH

```solidity
function recordOvercommittedBeaconChainETH(address overcommittedPodOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external
```

Records an overcommitment event on behalf of a staker. The staker's beaconChainETH shares are decremented by `amount`.

_Only callable by EigenPodManager._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| overcommittedPodOwner | address | is the pod owner to be slashed |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy in case it must be removed, |
| amount | uint256 | is the amount to decrement the slashedAddress's beaconChainETHStrategy shares |

### depositIntoStrategy

```solidity
function depositIntoStrategy(contract IStrategy strategy, contract IERC20 token, uint256 amount) external returns (uint256 shares)
```

Deposits `amount` of `token` into the specified `strategy`, with the resultant shares credited to `msg.sender`

_The `msg.sender` must have previously approved this contract to transfer at least `amount` of `token` on their behalf.
Cannot be called by an address that is 'frozen' (this function will revert if the `msg.sender` is frozen).

WARNING: Depositing tokens that allow reentrancy (eg. ERC-777) into a strategy is not recommended.  This can lead to attack vectors
         where the token balance and corresponding strategy shares are not in sync upon reentrancy._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | contract IStrategy | is the specified strategy where deposit is to be made, |
| token | contract IERC20 | is the denomination in which the deposit is to be made, |
| amount | uint256 | is the amount of token to be deposited in the strategy by the depositor |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of new shares in the `strategy` created as part of the action. |

### depositIntoStrategyWithSignature

```solidity
function depositIntoStrategyWithSignature(contract IStrategy strategy, contract IERC20 token, uint256 amount, address staker, uint256 expiry, bytes signature) external returns (uint256 shares)
```

Used for depositing an asset into the specified strategy with the resultant shares credited to `staker`,
who must sign off on the action.
Note that the assets are transferred out/from the `msg.sender`, not from the `staker`; this function is explicitly designed 
purely to help one address deposit 'for' another.

_The `msg.sender` must have previously approved this contract to transfer at least `amount` of `token` on their behalf.
A signature is required for this function to eliminate the possibility of griefing attacks, specifically those
targeting stakers who may be attempting to undelegate.
Cannot be called on behalf of a staker that is 'frozen' (this function will revert if the `staker` is frozen).

 WARNING: Depositing tokens that allow reentrancy (eg. ERC-777) into a strategy is not recommended.  This can lead to attack vectors
         where the token balance and corresponding strategy shares are not in sync upon reentrancy_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | contract IStrategy | is the specified strategy where deposit is to be made, |
| token | contract IERC20 | is the denomination in which the deposit is to be made, |
| amount | uint256 | is the amount of token to be deposited in the strategy by the depositor |
| staker | address | the staker that the deposited assets will be credited to |
| expiry | uint256 | the timestamp at which the signature expires |
| signature | bytes | is a valid signature from the `staker`. either an ECDSA signature if the `staker` is an EOA, or data to forward following EIP-1271 if the `staker` is a contract |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of new shares in the `strategy` created as part of the action. |

### undelegate

```solidity
function undelegate() external
```

Called by a staker to undelegate entirely from EigenLayer. The staker must first withdraw all of their existing deposits
(through use of the `queueWithdrawal` function), or else otherwise have never deposited in EigenLayer prior to delegating.

### queueWithdrawal

```solidity
function queueWithdrawal(uint256[] strategyIndexes, contract IStrategy[] strategies, uint256[] shares, address withdrawer, bool undelegateIfPossible) external returns (bytes32)
```

Called by a staker to queue a withdrawal of the given amount of `shares` from each of the respective given `strategies`.

_Stakers will complete their withdrawal by calling the 'completeQueuedWithdrawal' function.
User shares are decreased in this function, but the total number of shares in each strategy remains the same.
The total number of shares is decremented in the 'completeQueuedWithdrawal' function instead, which is where
the funds are actually sent to the user through use of the strategies' 'withdrawal' function. This ensures
that the value per share reported by each strategy will remain consistent, and that the shares will continue
to accrue gains during the enforced withdrawal waiting period.
Strategies are removed from `stakerStrategyList` by swapping the last entry with the entry to be removed, then
popping off the last entry in `stakerStrategyList`. The simplest way to calculate the correct `strategyIndexes` to input
is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
`stakerStrategyList` to lowest index
Note that if the withdrawal includes shares in the enshrined 'beaconChainETH' strategy, then it must *only* include shares in this strategy, and
`withdrawer` must match the caller's address. The first condition is because slashing of queued withdrawals cannot be guaranteed 
for Beacon Chain ETH (since we cannot trigger a withdrawal from the beacon chain through a smart contract) and the second condition is because shares in
the enshrined 'beaconChainETH' strategy technically represent non-fungible positions (deposits to the Beacon Chain, each pointed at a specific EigenPod)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategyIndexes | uint256[] | is a list of the indices in `stakerStrategyList[msg.sender]` that correspond to the strategies for which `msg.sender` is withdrawing 100% of their shares |
| strategies | contract IStrategy[] | The Strategies to withdraw from |
| shares | uint256[] | The amount of shares to withdraw from each of the respective Strategies in the `strategies` array |
| withdrawer | address | The address that can complete the withdrawal and will receive any withdrawn funds or shares upon completing the withdrawal |
| undelegateIfPossible | bool | If this param is marked as 'true' *and the withdrawal will result in `msg.sender` having no shares in any Strategy,* then this function will also make an internal call to `undelegate(msg.sender)` to undelegate the `msg.sender`. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bytes32 | The 'withdrawalRoot' of the newly created Queued Withdrawal |

### completeQueuedWithdrawal

```solidity
function completeQueuedWithdrawal(struct IStrategyManager.QueuedWithdrawal queuedWithdrawal, contract IERC20[] tokens, uint256 middlewareTimesIndex, bool receiveAsTokens) external
```

Used to complete the specified `queuedWithdrawal`. The function caller must match `queuedWithdrawal.withdrawer`

_middlewareTimesIndex should be calculated off chain before calling this function by finding the first index that satisfies `slasher.canWithdraw`_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| queuedWithdrawal | struct IStrategyManager.QueuedWithdrawal | The QueuedWithdrawal to complete. |
| tokens | contract IERC20[] | Array in which the i-th entry specifies the `token` input to the 'withdraw' function of the i-th Strategy in the `strategies` array of the `queuedWithdrawal`. This input can be provided with zero length if `receiveAsTokens` is set to 'false' (since in that case, this input will be unused) |
| middlewareTimesIndex | uint256 | is the index in the operator that the staker who triggered the withdrawal was delegated to's middleware times array |
| receiveAsTokens | bool | If true, the shares specified in the queued withdrawal will be withdrawn from the specified strategies themselves and sent to the caller, through calls to `queuedWithdrawal.strategies[i].withdraw`. If false, then the shares in the specified strategies will simply be transferred to the caller directly. |

### completeQueuedWithdrawals

```solidity
function completeQueuedWithdrawals(struct IStrategyManager.QueuedWithdrawal[] queuedWithdrawals, contract IERC20[][] tokens, uint256[] middlewareTimesIndexes, bool[] receiveAsTokens) external
```

Used to complete the specified `queuedWithdrawals`. The function caller must match `queuedWithdrawals[...].withdrawer`

_Array-ified version of `completeQueuedWithdrawal`
middlewareTimesIndex should be calculated off chain before calling this function by finding the first index that satisfies `slasher.canWithdraw`_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| queuedWithdrawals | struct IStrategyManager.QueuedWithdrawal[] | The QueuedWithdrawals to complete. |
| tokens | contract IERC20[][] | Array of tokens for each QueuedWithdrawal. See `completeQueuedWithdrawal` for the usage of a single array. |
| middlewareTimesIndexes | uint256[] | One index to reference per QueuedWithdrawal. See `completeQueuedWithdrawal` for the usage of a single index. |
| receiveAsTokens | bool[] | If true, the shares specified in the queued withdrawal will be withdrawn from the specified strategies themselves and sent to the caller, through calls to `queuedWithdrawal.strategies[i].withdraw`. If false, then the shares in the specified strategies will simply be transferred to the caller directly. |

### slashShares

```solidity
function slashShares(address slashedAddress, address recipient, contract IStrategy[] strategies, contract IERC20[] tokens, uint256[] strategyIndexes, uint256[] shareAmounts) external
```

Slashes the shares of a 'frozen' operator (or a staker delegated to one)

_strategies are removed from `stakerStrategyList` by swapping the last entry with the entry to be removed, then
popping off the last entry in `stakerStrategyList`. The simplest way to calculate the correct `strategyIndexes` to input
is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
`stakerStrategyList` to lowest index_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| slashedAddress | address | is the frozen address that is having its shares slashed |
| recipient | address | is the address that will receive the slashed funds, which could e.g. be a harmed party themself, or a MerkleDistributor-type contract that further sub-divides the slashed funds. |
| strategies | contract IStrategy[] | Strategies to slash |
| tokens | contract IERC20[] | The tokens to use as input to the `withdraw` function of each of the provided `strategies` |
| strategyIndexes | uint256[] | is a list of the indices in `stakerStrategyList[msg.sender]` that correspond to the strategies for which `msg.sender` is withdrawing 100% of their shares |
| shareAmounts | uint256[] | The amount of shares to slash in each of the provided `strategies` |

### slashQueuedWithdrawal

```solidity
function slashQueuedWithdrawal(address recipient, struct IStrategyManager.QueuedWithdrawal queuedWithdrawal, contract IERC20[] tokens, uint256[] indicesToSkip) external
```

Slashes an existing queued withdrawal that was created by a 'frozen' operator (or a staker delegated to one)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipient | address | The funds in the slashed withdrawal are withdrawn as tokens to this address. |
| queuedWithdrawal | struct IStrategyManager.QueuedWithdrawal | The previously queued withdrawal to be slashed |
| tokens | contract IERC20[] | Array in which the i-th entry specifies the `token` input to the 'withdraw' function of the i-th Strategy in the `strategies` array of the `queuedWithdrawal`. |
| indicesToSkip | uint256[] | Optional input parameter -- indices in the `strategies` array to skip (i.e. not call the 'withdraw' function on). This input exists so that, e.g., if the slashed QueuedWithdrawal contains a malicious strategy in the `strategies` array which always reverts on calls to its 'withdraw' function, then the malicious strategy can be skipped (with the shares in effect "burned"), while the non-malicious strategies are still called as normal. |

### setWithdrawalDelayBlocks

```solidity
function setWithdrawalDelayBlocks(uint256 _withdrawalDelayBlocks) external
```

Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _withdrawalDelayBlocks | uint256 | new value of `withdrawalDelayBlocks`. |

### setStrategyWhitelister

```solidity
function setStrategyWhitelister(address newStrategyWhitelister) external
```

Owner-only function to change the `strategyWhitelister` address.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newStrategyWhitelister | address | new address for the `strategyWhitelister`. |

### addStrategiesToDepositWhitelist

```solidity
function addStrategiesToDepositWhitelist(contract IStrategy[] strategiesToWhitelist) external
```

Owner-only function that adds the provided Strategies to the 'whitelist' of strategies that stakers can deposit into

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategiesToWhitelist | contract IStrategy[] | Strategies that will be added to the `strategyIsWhitelistedForDeposit` mapping (if they aren't in it already) |

### removeStrategiesFromDepositWhitelist

```solidity
function removeStrategiesFromDepositWhitelist(contract IStrategy[] strategiesToRemoveFromWhitelist) external
```

Owner-only function that removes the provided Strategies from the 'whitelist' of strategies that stakers can deposit into

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategiesToRemoveFromWhitelist | contract IStrategy[] | Strategies that will be removed to the `strategyIsWhitelistedForDeposit` mapping (if they are in it) |

### _addShares

```solidity
function _addShares(address depositor, contract IStrategy strategy, uint256 shares) internal
```

This function adds `shares` for a given `strategy` to the `depositor` and runs through the necessary update logic.

_In particular, this function calls `delegation.increaseDelegatedShares(depositor, strategy, shares)` to ensure that all
delegated shares are tracked, increases the stored share amount in `stakerStrategyShares[depositor][strategy]`, and adds `strategy`
to the `depositor`'s list of strategies, if it is not in the list already._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address to add shares to |
| strategy | contract IStrategy | The Strategy in which the `depositor` is receiving shares |
| shares | uint256 | The amount of shares to grant to the `depositor` |

### _depositIntoStrategy

```solidity
function _depositIntoStrategy(address depositor, contract IStrategy strategy, contract IERC20 token, uint256 amount) internal returns (uint256 shares)
```

Internal function in which `amount` of ERC20 `token` is transferred from `msg.sender` to the Strategy-type contract
`strategy`, with the resulting shares credited to `depositor`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address that will be credited with the new shares. |
| strategy | contract IStrategy | The Strategy contract to deposit into. |
| token | contract IERC20 | The ERC20 token to deposit. |
| amount | uint256 | The amount of `token` to deposit. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of *new* shares in `strategy` that have been credited to the `depositor`. |

### _removeShares

```solidity
function _removeShares(address depositor, uint256 strategyIndex, contract IStrategy strategy, uint256 shareAmount) internal returns (bool)
```

Decreases the shares that `depositor` holds in `strategy` by `shareAmount`.

_If the amount of shares represents all of the depositor`s shares in said strategy,
then the strategy is removed from stakerStrategyList[depositor] and 'true' is returned. Otherwise 'false' is returned._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address to decrement shares from |
| strategyIndex | uint256 | The `strategyIndex` input for the internal `_removeStrategyFromStakerStrategyList`. Used only in the case that the removal of the depositor's shares results in them having zero remaining shares in the `strategy` |
| strategy | contract IStrategy | The strategy for which the `depositor`'s shares are being decremented |
| shareAmount | uint256 | The amount of shares to decrement |

### _removeStrategyFromStakerStrategyList

```solidity
function _removeStrategyFromStakerStrategyList(address depositor, uint256 strategyIndex, contract IStrategy strategy) internal
```

Removes `strategy` from `depositor`'s dynamic array of strategies, i.e. from `stakerStrategyList[depositor]`

_the provided `strategyIndex` input is optimistically used to find the strategy quickly in the list. If the specified
index is incorrect, then we revert to a brute-force search._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The user whose array will have an entry removed |
| strategyIndex | uint256 | Preferably the index of `strategy` in `stakerStrategyList[depositor]`. If the input is incorrect, then a brute-force fallback routine will be used to find the correct input |
| strategy | contract IStrategy | The Strategy to remove from `stakerStrategyList[depositor]` |

### _completeQueuedWithdrawal

```solidity
function _completeQueuedWithdrawal(struct IStrategyManager.QueuedWithdrawal queuedWithdrawal, contract IERC20[] tokens, uint256 middlewareTimesIndex, bool receiveAsTokens) internal
```

Internal function for completing the given `queuedWithdrawal`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| queuedWithdrawal | struct IStrategyManager.QueuedWithdrawal | The QueuedWithdrawal to complete |
| tokens | contract IERC20[] | The ERC20 tokens to provide as inputs to `Strategy.withdraw`. Only relevant if `receiveAsTokens = true` |
| middlewareTimesIndex | uint256 | Passed on as an input to the `slasher.canWithdraw` function, to ensure the withdrawal is completable. |
| receiveAsTokens | bool | If marked 'true', then calls will be passed on to the `Strategy.withdraw` function for each strategy. If marked 'false', then the shares will simply be internally transferred to the `msg.sender`. |

### _undelegate

```solidity
function _undelegate(address depositor) internal
```

If the `depositor` has no existing shares, then they can `undelegate` themselves.
This allows people a "hard reset" in their relationship with EigenLayer after withdrawing all of their stake.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The address to undelegate. Passed on as an input to the `delegation.undelegate` function. |

### _withdrawBeaconChainETH

```solidity
function _withdrawBeaconChainETH(address staker, address recipient, uint256 amount) internal
```

### _setWithdrawalDelayBlocks

```solidity
function _setWithdrawalDelayBlocks(uint256 _withdrawalDelayBlocks) internal
```

internal function for changing the value of `withdrawalDelayBlocks`. Also performs sanity check and emits an event.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _withdrawalDelayBlocks | uint256 | The new value for `withdrawalDelayBlocks` to take. |

### _setStrategyWhitelister

```solidity
function _setStrategyWhitelister(address newStrategyWhitelister) internal
```

Internal function for modifying the `strategyWhitelister`. Used inside of the `setStrategyWhitelister` and `initialize` functions.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newStrategyWhitelister | address | The new address for the `strategyWhitelister` to take. |

### getDeposits

```solidity
function getDeposits(address depositor) external view returns (contract IStrategy[], uint256[])
```

Get all details on the depositor's deposits and corresponding shares

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | The staker of interest, whose deposits this function will fetch |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | contract IStrategy[] | (depositor's strategies, shares in these strategies) |
| [1] | uint256[] |  |

### stakerStrategyListLength

```solidity
function stakerStrategyListLength(address staker) external view returns (uint256)
```

Simple getter function that returns `stakerStrategyList[staker].length`.

### calculateWithdrawalRoot

```solidity
function calculateWithdrawalRoot(struct IStrategyManager.QueuedWithdrawal queuedWithdrawal) public pure returns (bytes32)
```

Returns the keccak256 hash of `queuedWithdrawal`.

