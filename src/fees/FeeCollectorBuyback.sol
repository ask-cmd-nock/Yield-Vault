// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ISwapRouterV3} from "../interfaces/ISwapRouterV3.sol";

interface IRewardsDistributor {
    function notifyRewardAmount(uint256 reward) external;
}

/// @title FeeCollectorBuyback
/// @notice Set as the Morpho Vault V2 `performanceFeeRecipient`. Fee accrual arrives
///         as vault shares; `execute()`:
///           1. redeems all fee shares for the underlying (USDG),
///           2. pays the caller a small incentive,
///           3. swaps `buybackBps` of the remainder into the utility token via Uniswap,
///           4. burns `burnBps` of the bought tokens and streams the rest to
///              BoostedStaking as staker rewards,
///           5. forwards the remaining USDG to the treasury.
/// @dev `execute` is keeper-gated (not fully permissionless) so that `minBuybackOut`
///      cannot be griefed to 0 by an arbitrary caller sandwiching the swap. Keepers are
///      owner-managed; a permissionless TWAP-guarded variant is a documented upgrade.
contract FeeCollectorBuyback is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ─────────────────────────── Config ─────────────────────────── */

    IERC4626 public immutable vault;
    IERC20 public immutable asset; // vault underlying (USDG)
    IERC20 public immutable buybackToken; // utility token (TEST placeholder / RHVY)
    ISwapRouterV3 public immutable swapRouter;

    address public staking; // BoostedStaking, receives bought tokens as rewards
    address public treasury;
    mapping(address => bool) public isKeeper;

    uint16 public buybackBps = 5_000; // share of harvested USDG swapped to utility token
    uint16 public burnBps = 2_000; // share of bought tokens burned
    uint16 public callerIncentiveBps = 10; // 0.10% of harvest, paid in USDG
    uint24 public poolFee = 3_000; // Uniswap fee tier for USDG→token
    uint32 public minInterval = 6 hours; // rate limit between executions
    uint64 public lastExecuted;

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_CALLER_INCENTIVE_BPS = 100; // 1%
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /* ─────────────────────────── Events ─────────────────────────── */

    event Executed(
        address indexed keeper,
        uint256 harvested,
        uint256 incentive,
        uint256 spentOnBuyback,
        uint256 bought,
        uint256 burned,
        uint256 toStakers,
        uint256 toTreasury
    );
    event KeeperSet(address indexed keeper, bool enabled);
    event StakingSet(address indexed staking);
    event TreasurySet(address indexed treasury);
    event ParamsSet(uint16 buybackBps, uint16 burnBps, uint16 callerIncentiveBps, uint24 poolFee, uint32 minInterval);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    /* ─────────────────────────── Errors ─────────────────────────── */

    error ZeroAddress();
    error NotKeeper();
    error TooSoon();
    error NothingToExecute();
    error MinOutZero();
    error InvalidParams();

    /* ───────────────────────── Constructor ──────────────────────── */

    constructor(
        IERC4626 vault_,
        IERC20 buybackToken_,
        ISwapRouterV3 swapRouter_,
        address treasury_,
        address owner_
    ) Ownable(owner_) {
        if (
            address(vault_) == address(0) || address(buybackToken_) == address(0)
                || address(swapRouter_) == address(0) || treasury_ == address(0)
        ) revert ZeroAddress();
        vault = vault_;
        asset = IERC20(vault_.asset());
        buybackToken = buybackToken_;
        swapRouter = swapRouter_;
        treasury = treasury_;
        isKeeper[owner_] = true;
    }

    /* ─────────────────────────── Execute ────────────────────────── */

    /// @notice Harvest fee shares and run the buyback split.
    /// @param minBuybackOut Minimum utility tokens received for the swap leg
    ///        (slippage guard — keeper computes off-chain from a fresh quote).
    function execute(uint256 minBuybackOut) external nonReentrant whenNotPaused {
        if (!isKeeper[msg.sender]) revert NotKeeper();
        if (block.timestamp < uint256(lastExecuted) + minInterval) revert TooSoon();
        lastExecuted = uint64(block.timestamp);

        // 1. Redeem all accrued fee shares.
        uint256 shares = vault.balanceOf(address(this));
        if (shares > 0) vault.redeem(shares, address(this), address(this));

        uint256 harvested = asset.balanceOf(address(this));
        if (harvested == 0) revert NothingToExecute();

        // 2. Caller incentive.
        uint256 incentive = (harvested * callerIncentiveBps) / BPS;
        if (incentive > 0) asset.safeTransfer(msg.sender, incentive);
        uint256 remaining = harvested - incentive;

        // 3. Buyback leg.
        uint256 buyAmount = (remaining * buybackBps) / BPS;
        uint256 bought;
        uint256 burned;
        uint256 toStakers;
        if (buyAmount > 0) {
            if (minBuybackOut == 0) revert MinOutZero();
            asset.forceApprove(address(swapRouter), buyAmount);
            bought = swapRouter.exactInputSingle(
                ISwapRouterV3.ExactInputSingleParams({
                    tokenIn: address(asset),
                    tokenOut: address(buybackToken),
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: buyAmount,
                    amountOutMinimum: minBuybackOut,
                    sqrtPriceLimitX96: 0
                })
            );

            // 4. Burn / staker-reward split of the bought tokens.
            burned = (bought * burnBps) / BPS;
            if (burned > 0) buybackToken.safeTransfer(BURN_ADDRESS, burned);
            toStakers = bought - burned;
            if (toStakers > 0 && staking != address(0)) {
                buybackToken.forceApprove(staking, toStakers);
                IRewardsDistributor(staking).notifyRewardAmount(toStakers);
            } else if (toStakers > 0) {
                // No staking contract wired yet: park with treasury instead of bricking.
                buybackToken.safeTransfer(treasury, toStakers);
            }
        }

        // 5. Treasury remainder.
        uint256 toTreasury = remaining - buyAmount;
        if (toTreasury > 0) asset.safeTransfer(treasury, toTreasury);

        emit Executed(msg.sender, harvested, incentive, buyAmount, bought, burned, toStakers, toTreasury);
    }

    /* ─────────────────────────── Admin ──────────────────────────── */

    function setKeeper(address keeper, bool enabled) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        isKeeper[keeper] = enabled;
        emit KeeperSet(keeper, enabled);
    }

    function setStaking(address staking_) external onlyOwner {
        staking = staking_; // zero allowed: routes staker share to treasury
        emit StakingSet(staking_);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function setParams(uint16 buybackBps_, uint16 burnBps_, uint16 callerIncentiveBps_, uint24 poolFee_, uint32 minInterval_)
        external
        onlyOwner
    {
        if (buybackBps_ > BPS || burnBps_ > BPS) revert InvalidParams();
        if (callerIncentiveBps_ > MAX_CALLER_INCENTIVE_BPS) revert InvalidParams();
        if (poolFee_ == 0 || minInterval_ > 7 days) revert InvalidParams();
        buybackBps = buybackBps_;
        burnBps = burnBps_;
        callerIncentiveBps = callerIncentiveBps_;
        poolFee = poolFee_;
        minInterval = minInterval_;
        emit ParamsSet(buybackBps_, burnBps_, callerIncentiveBps_, poolFee_, minInterval_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Owner escape hatch for tokens stuck in this contract.
    /// @dev Owner is expected to sit behind the protocol timelock.
    function rescue(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        token.safeTransfer(to, amount);
        emit Rescued(address(token), to, amount);
    }
}
