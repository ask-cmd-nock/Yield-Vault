// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import {MarketParams} from "./IMorphoTypes.sol";

/// @title IMorphoMarketV1AdapterV2 (subset)
/// @notice Adapter connecting a Morpho Vault V2 to Morpho Market V1 markets.
/// @dev Id scheme used by the adapter (needed when setting vault caps):
///        ids[0] = keccak256(abi.encode("this", adapter))                      — whole-adapter id
///        ids[1] = keccak256(abi.encode("collateralToken", collateralToken))   — per-collateral id
///        ids[2] = keccak256(abi.encode("this/marketParams", adapter, params)) — per-market id
///      Vault cap functions take the raw idData (pre-hash bytes), not the hash.
interface IMorphoMarketV1AdapterV2 {
    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function adapterId() external view returns (bytes32);
    function marketIds(uint256 index) external view returns (bytes32);
    function marketIdsLength() external view returns (uint256);
    function supplyShares(bytes32 marketId) external view returns (uint256);
    function allocation(MarketParams memory marketParams) external view returns (uint256);
    function expectedSupplyAssets(bytes32 marketId) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}

interface IMorphoMarketV1AdapterV2Factory {
    function morpho() external view returns (address);
    function adaptiveCurveIrm() external view returns (address);
    function morphoMarketV1AdapterV2(address parentVault) external view returns (address);
    function isMorphoMarketV1AdapterV2(address account) external view returns (bool);
    function createMorphoMarketV1AdapterV2(address parentVault) external returns (address);
}
