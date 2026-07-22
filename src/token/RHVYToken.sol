// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title RHVYToken
/// @notice Utility & governance token for RH Yield Vault.
///         Fixed supply, minted once to the treasury at deployment; no further minting.
///         ERC20Votes checkpoints enable plugging into an OZ Governor later,
///         ERC20Permit enables gasless approvals.
/// @dev "RHVY" is a placeholder brand. Do NOT ship a name/symbol that uses or implies
///      the Robinhood trademark. During integration testing the already-deployed TEST
///      token (see script/config/robinhood.json `utilityToken`) stands in for this
///      contract; all periphery contracts take the token address as a parameter so the
///      two are interchangeable.
contract RHVYToken is ERC20, ERC20Permit, ERC20Votes {
    /// @notice Total (and maximum) supply: 1 billion tokens.
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    error ZeroAddress();

    /// @param name_ Token name (e.g. "RH Yield Vault Token" — no "Robinhood").
    /// @param symbol_ Token symbol (e.g. "RHVY").
    /// @param treasury Receives the entire genesis supply (protocol multisig).
    constructor(string memory name_, string memory symbol_, address treasury)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        if (treasury == address(0)) revert ZeroAddress();
        _mint(treasury, MAX_SUPPLY);
    }

    /* Overrides required by Solidity for multiple inheritance. */

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
