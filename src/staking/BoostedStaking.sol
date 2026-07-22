// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title BoostedStaking
/// @notice Stake the utility token under a time-lock tier and earn a share of the
///         protocol fee stream (paid in the reward token by FeeCollectorBuyback).
///         Longer locks earn a reward multiplier ("boost").
///
///         IMPORTANT DESIGN INVARIANT: boosts apply to REWARD WEIGHT ONLY. They never
///         touch the yield vault's ERC-4626 share pricing, which must stay fungible.
///
/// @dev Synthetix-style reward accumulator over "weight" (amount × tier multiplier)
///      instead of raw amount. O(1) per action, no loops over stakers.
///      Positions are per-(user, id); a user may hold many positions across tiers.
contract BoostedStaking is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /* ─────────────────────────── Types ─────────────────────────── */

    struct Tier {
        uint32 lockDuration; // seconds the stake is locked
        uint32 multiplierBps; // reward weight multiplier, 10_000 = 1x
        bool enabled; // disabled tiers reject new stakes; existing stakes unaffected
    }

    struct Position {
        uint128 amount; // staked tokens (0 once withdrawn)
        uint128 weight; // amount × multiplierBps / 10_000
        uint64 unlockAt; // timestamp the stake can be withdrawn
        uint256 rewardPerWeightPaid; // accumulator snapshot at last settle
        uint256 rewards; // settled, unclaimed rewards
    }

    /* ────────────────────────── Constants ───────────────────────── */

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_MULTIPLIER_BPS = 50_000; // 5x cap
    uint256 public constant MAX_LOCK = 4 * 365 days;
    uint256 private constant PRECISION = 1e18;

    /* ─────────────────────────── Storage ────────────────────────── */

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    Tier[] public tiers;
    mapping(address => Position[]) public positions;

    uint256 public totalStaked;
    uint256 public totalWeight;

    /// @notice Address allowed to feed rewards (the FeeCollectorBuyback contract).
    address public distributor;
    uint256 public rewardsDuration = 7 days;
    uint256 public periodFinish;
    uint256 public rewardRate; // reward tokens streamed per second
    uint256 public lastUpdateTime;
    uint256 public rewardPerWeightStored;

    /* ─────────────────────────── Events ─────────────────────────── */

    event Staked(address indexed user, uint256 indexed positionId, uint256 amount, uint256 tierId, uint256 weight, uint256 unlockAt);
    event Withdrawn(address indexed user, uint256 indexed positionId, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed positionId, uint256 reward);
    event RewardNotified(uint256 reward, uint256 rewardRate, uint256 periodFinish);
    event TierAdded(uint256 indexed tierId, uint32 lockDuration, uint32 multiplierBps);
    event TierEnabled(uint256 indexed tierId, bool enabled);
    event DistributorSet(address indexed distributor);
    event RewardsDurationSet(uint256 duration);

    /* ─────────────────────────── Errors ─────────────────────────── */

    error ZeroAddress();
    error ZeroAmount();
    error InvalidTier();
    error TierDisabled();
    error StillLocked();
    error PositionClosed();
    error NotDistributor();
    error RewardTooHigh();
    error PeriodActive();
    error InvalidParams();

    /* ───────────────────────── Constructor ──────────────────────── */

    /// @param stakingToken_ Token users stake (utility token; TEST during testing).
    /// @param rewardToken_ Token rewards are paid in (typically the same token,
    ///        supplied by the buyback loop).
    /// @param owner_ Admin (protocol multisig / timelock).
    constructor(IERC20 stakingToken_, IERC20 rewardToken_, address owner_) Ownable(owner_) {
        if (address(stakingToken_) == address(0) || address(rewardToken_) == address(0)) revert ZeroAddress();
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;

        // Default tiers: 1 week 1x, 1 month 1.25x, 3 months 1.5x, 1 year 2.5x.
        _addTier(7 days, 10_000);
        _addTier(30 days, 12_500);
        _addTier(90 days, 15_000);
        _addTier(365 days, 25_000);
    }

    /* ──────────────────────── Reward accrual ────────────────────── */

    function _rewardPerWeight() internal view returns (uint256) {
        if (totalWeight == 0) return rewardPerWeightStored;
        uint256 last = block.timestamp < periodFinish ? block.timestamp : periodFinish;
        return rewardPerWeightStored + ((last - lastUpdateTime) * rewardRate * PRECISION) / totalWeight;
    }

    function _updateGlobal() internal {
        rewardPerWeightStored = _rewardPerWeight();
        lastUpdateTime = block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function _settle(address user, uint256 positionId) internal {
        _updateGlobal();
        Position storage p = positions[user][positionId];
        p.rewards += (uint256(p.weight) * (rewardPerWeightStored - p.rewardPerWeightPaid)) / PRECISION;
        p.rewardPerWeightPaid = rewardPerWeightStored;
    }

    /// @notice Pending rewards of a position.
    function earned(address user, uint256 positionId) public view returns (uint256) {
        Position storage p = positions[user][positionId];
        return p.rewards + (uint256(p.weight) * (_rewardPerWeight() - p.rewardPerWeightPaid)) / PRECISION;
    }

    /* ─────────────────────────── Staking ────────────────────────── */

    /// @notice Stake `amount` under tier `tierId`. Creates a new position.
    /// @return positionId Index of the new position in `positions[msg.sender]`.
    function stake(uint256 amount, uint256 tierId) external nonReentrant whenNotPaused returns (uint256 positionId) {
        if (amount == 0) revert ZeroAmount();
        if (tierId >= tiers.length) revert InvalidTier();
        Tier memory tier = tiers[tierId];
        if (!tier.enabled) revert TierDisabled();

        _updateGlobal();

        uint256 weight = (amount * tier.multiplierBps) / BPS;
        positionId = positions[msg.sender].length;
        positions[msg.sender].push(
            Position({
                amount: amount.toUint128(),
                weight: weight.toUint128(),
                unlockAt: (block.timestamp + tier.lockDuration).toUint64(),
                rewardPerWeightPaid: rewardPerWeightStored,
                rewards: 0
            })
        );

        totalStaked += amount;
        totalWeight += weight;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, positionId, amount, tierId, weight, block.timestamp + tier.lockDuration);
    }

    /// @notice Withdraw a matured position and claim its rewards.
    /// @dev Withdrawals are never pausable.
    function withdraw(uint256 positionId) external nonReentrant {
        Position storage p = positions[msg.sender][positionId];
        uint256 amount = p.amount;
        if (amount == 0) revert PositionClosed();
        if (block.timestamp < p.unlockAt) revert StillLocked();

        _settle(msg.sender, positionId);

        totalStaked -= amount;
        totalWeight -= p.weight;
        p.amount = 0;
        p.weight = 0;

        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, positionId, amount);

        _payReward(positionId);
    }

    /// @notice Claim accrued rewards on a position (lock does not block claiming).
    function claim(uint256 positionId) external nonReentrant {
        if (positionId >= positions[msg.sender].length) revert PositionClosed();
        _settle(msg.sender, positionId);
        _payReward(positionId);
    }

    function _payReward(uint256 positionId) internal {
        Position storage p = positions[msg.sender][positionId];
        uint256 reward = p.rewards;
        if (reward == 0) return;
        p.rewards = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, positionId, reward);
    }

    function positionsLength(address user) external view returns (uint256) {
        return positions[user].length;
    }

    function tiersLength() external view returns (uint256) {
        return tiers.length;
    }

    /* ──────────────────────── Distribution ──────────────────────── */

    /// @notice Pull `reward` tokens from the distributor and stream them over
    ///         `rewardsDuration` (leftover of an active period rolls forward).
    function notifyRewardAmount(uint256 reward) external nonReentrant {
        if (msg.sender != distributor) revert NotDistributor();
        if (reward == 0) revert ZeroAmount();

        _updateGlobal();
        rewardToken.safeTransferFrom(msg.sender, address(this), reward);

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 leftover = (periodFinish - block.timestamp) * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Overflow/solvency guard: the contract must hold enough reward tokens to
        // cover the whole period. When staking and reward tokens are the same,
        // staked principal is excluded from the reward budget.
        uint256 budget = rewardToken.balanceOf(address(this));
        if (rewardToken == stakingToken) budget -= totalStaked;
        if (rewardRate > budget / rewardsDuration) revert RewardTooHigh();

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardNotified(reward, rewardRate, periodFinish);
    }

    /* ─────────────────────────── Admin ──────────────────────────── */

    function addTier(uint32 lockDuration, uint32 multiplierBps) external onlyOwner {
        _addTier(lockDuration, multiplierBps);
    }

    function _addTier(uint32 lockDuration, uint32 multiplierBps) internal {
        if (lockDuration == 0 || lockDuration > MAX_LOCK) revert InvalidParams();
        if (multiplierBps < BPS || multiplierBps > MAX_MULTIPLIER_BPS) revert InvalidParams();
        tiers.push(Tier({lockDuration: lockDuration, multiplierBps: multiplierBps, enabled: true}));
        emit TierAdded(tiers.length - 1, lockDuration, multiplierBps);
    }

    function setTierEnabled(uint256 tierId, bool enabled) external onlyOwner {
        if (tierId >= tiers.length) revert InvalidTier();
        tiers[tierId].enabled = enabled;
        emit TierEnabled(tierId, enabled);
    }

    function setDistributor(address distributor_) external onlyOwner {
        if (distributor_ == address(0)) revert ZeroAddress();
        distributor = distributor_;
        emit DistributorSet(distributor_);
    }

    /// @notice Change stream length; only between reward periods so accounting is clean.
    function setRewardsDuration(uint256 duration) external onlyOwner {
        if (block.timestamp < periodFinish) revert PeriodActive();
        if (duration == 0 || duration > 365 days) revert InvalidParams();
        rewardsDuration = duration;
        emit RewardsDurationSet(duration);
    }

    /// @notice Pause new stakes. Withdraw and claim are intentionally not pausable.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
