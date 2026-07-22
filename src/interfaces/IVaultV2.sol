// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IVaultV2 (subset)
/// @notice Minimal interface of morpho-org/vault-v2 `IVaultV2`, restricted to the
///         functions this project reads or calls. Signatures copied verbatim from the
///         official repository so calldata built with `abi.encodeCall` matches the
///         deployed bytecode on Robinhood Chain.
interface IVaultV2 is IERC4626 {
    /* ROLES / STATE */
    function owner() external view returns (address);
    function curator() external view returns (address);
    function isSentinel(address account) external view returns (bool);
    function isAllocator(address account) external view returns (bool);
    function isAdapter(address account) external view returns (bool);
    function allocation(bytes32 id) external view returns (uint256);
    function absoluteCap(bytes32 id) external view returns (uint256);
    function relativeCap(bytes32 id) external view returns (uint256);
    function timelock(bytes4 selector) external view returns (uint256);
    function executableAt(bytes memory data) external view returns (uint256);
    function performanceFee() external view returns (uint96);
    function performanceFeeRecipient() external view returns (address);
    function managementFee() external view returns (uint96);

    /* OWNER */
    function setOwner(address newOwner) external;
    function setCurator(address newCurator) external;
    function setIsSentinel(address account, bool isSentinel) external;
    function setName(string memory newName) external;
    function setSymbol(string memory newSymbol) external;

    /* TIMELOCK FLOW (curator submits, then the call itself executes) */
    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;

    /* CURATOR (timelocked) */
    function setIsAllocator(address account, bool newIsAllocator) external;
    function addAdapter(address account) external;
    function removeAdapter(address account) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function setPerformanceFee(uint256 newPerformanceFee) external;
    function setManagementFee(uint256 newManagementFee) external;
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external;
    function setManagementFeeRecipient(address newManagementFeeRecipient) external;
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external;

    /* ALLOCATOR */
    function allocate(address adapter, bytes memory data, uint256 assets) external;
    function deallocate(address adapter, bytes memory data, uint256 assets) external;
    function setLiquidityAdapterAndData(address newLiquidityAdapter, bytes memory newLiquidityData) external;

    /* MISC */
    function accrueInterest() external;
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256 penaltyShares);
}
