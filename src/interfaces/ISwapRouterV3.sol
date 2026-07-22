// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title ISwapRouterV3 (subset)
/// @notice Uniswap V3-style swap router, single-hop exact-input only.
/// @dev Robinhood Chain's canonical Uniswap router address goes in
///      script/config/robinhood.json (`swapRouter`). If the deployed router is
///      SwapRouter02 (no deadline field), adjust this struct before deploying.
interface ISwapRouterV3 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
