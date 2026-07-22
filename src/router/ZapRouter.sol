// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ISwapRouterV3} from "../interfaces/ISwapRouterV3.sol";

/// @title ZapRouter
/// @notice One-transaction "swap any supported stable → USDG → vault deposit".
///         Keeps the vault itself strictly single-asset (ERC-4626 compliant); this
///         router is stateless, ownerless, and holds no funds between transactions.
contract ZapRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC4626 public immutable vault;
    IERC20 public immutable usdg;
    ISwapRouterV3 public immutable swapRouter;

    event Zapped(address indexed sender, address indexed receiver, address tokenIn, uint256 amountIn, uint256 usdgIn, uint256 shares);

    error ZeroAddress();
    error ZeroAmount();

    constructor(IERC4626 vault_, ISwapRouterV3 swapRouter_) {
        if (address(vault_) == address(0) || address(swapRouter_) == address(0)) revert ZeroAddress();
        vault = vault_;
        usdg = IERC20(vault_.asset());
        swapRouter = swapRouter_;
    }

    /// @notice Swap `amountIn` of `tokenIn` to USDG (skipped if `tokenIn` is USDG)
    ///         and deposit the proceeds into the vault for `receiver`.
    /// @param poolFee Uniswap fee tier of the tokenIn/USDG pool.
    /// @param minUsdgOut Slippage floor for the swap leg.
    /// @return shares Vault shares minted to `receiver`.
    function zapIn(IERC20 tokenIn, uint256 amountIn, uint24 poolFee, uint256 minUsdgOut, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();

        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 usdgIn;
        if (tokenIn == usdg) {
            usdgIn = amountIn;
        } else {
            tokenIn.forceApprove(address(swapRouter), amountIn);
            usdgIn = swapRouter.exactInputSingle(
                ISwapRouterV3.ExactInputSingleParams({
                    tokenIn: address(tokenIn),
                    tokenOut: address(usdg),
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minUsdgOut,
                    sqrtPriceLimitX96: 0
                })
            );
        }

        usdg.forceApprove(address(vault), usdgIn);
        shares = vault.deposit(usdgIn, receiver);
        emit Zapped(msg.sender, receiver, address(tokenIn), amountIn, usdgIn, shares);
    }
}
