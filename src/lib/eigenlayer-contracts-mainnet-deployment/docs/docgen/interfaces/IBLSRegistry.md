# Solidity API

## IBLSRegistry

Adds BLS-specific functions to the base interface.

### ApkUpdate

```solidity
struct ApkUpdate {
  bytes32 apkHash;
  uint32 blockNumber;
}
```

### getCorrectApkHash

```solidity
function getCorrectApkHash(uint256 index, uint32 blockNumber) external returns (bytes32)
```

get hash of a historical aggregated public key corresponding to a given index;
called by checkSignatures in BLSSignatureChecker.sol.

### apkUpdates

```solidity
function apkUpdates(uint256 index) external view returns (struct IBLSRegistry.ApkUpdate)
```

returns the `ApkUpdate` struct at `index` in the list of APK updates

### apkHashes

```solidity
function apkHashes(uint256 index) external view returns (bytes32)
```

returns the APK hash that resulted from the `index`th APK update

### apkUpdateBlockNumbers

```solidity
function apkUpdateBlockNumbers(uint256 index) external view returns (uint32)
```

returns the block number at which the `index`th APK update occurred

### operatorWhitelister

```solidity
function operatorWhitelister() external view returns (address)
```

### operatorWhitelistEnabled

```solidity
function operatorWhitelistEnabled() external view returns (bool)
```

### whitelisted

```solidity
function whitelisted(address) external view returns (bool)
```

### setOperatorWhitelistStatus

```solidity
function setOperatorWhitelistStatus(bool _operatorWhitelistEnabled) external
```

### addToOperatorWhitelist

```solidity
function addToOperatorWhitelist(address[]) external
```

### removeFromWhitelist

```solidity
function removeFromWhitelist(address[] operators) external
```

