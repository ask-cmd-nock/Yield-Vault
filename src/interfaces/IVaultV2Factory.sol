// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @notice Verbatim from morpho-org/vault-v2. Deployed on Robinhood Chain at
///         0x9633D22Bb8F42f6f70DbbBe34c11EB9209769b8b (see script/config/robinhood.json).
interface IVaultV2Factory {
    event CreateVaultV2(address indexed owner, address indexed asset, bytes32 salt, address indexed newVaultV2);

    function isVaultV2(address account) external view returns (bool);
    function vaultV2(address owner, address asset, bytes32 salt) external view returns (address);
    function createVaultV2(address owner, address asset, bytes32 salt) external returns (address newVaultV2);
}
