// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @dev Market parameters of a Morpho (Market V1 / "Blue") market.
///      Mirrors morpho-org/morpho-blue `IMorpho.MarketParams`.
struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}
