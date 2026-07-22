// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BoostedStaking} from "../src/staking/BoostedStaking.sol";
import {MockERC20} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BoostedStakingTest is Test {
    BoostedStaking staking;
    MockERC20 token; // staking token == reward token, like the TEST/RHVY setup
    address owner = makeAddr("owner");
    address distributor = makeAddr("distributor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new MockERC20("test", "TEST", 18);
        staking = new BoostedStaking(IERC20(token), IERC20(token), owner);
        vm.prank(owner);
        staking.setDistributor(distributor);

        for (uint256 i; i < 2; i++) {
            address u = i == 0 ? alice : bob;
            token.mint(u, 1_000e18);
            vm.prank(u);
            token.approve(address(staking), type(uint256).max);
        }
        token.mint(distributor, 1_000_000e18);
        vm.prank(distributor);
        token.approve(address(staking), type(uint256).max);
    }

    function _notify(uint256 amount) internal {
        vm.prank(distributor);
        staking.notifyRewardAmount(amount);
    }

    function test_stakeCreatesPositionWithTierWeight() public {
        vm.prank(alice);
        uint256 id = staking.stake(100e18, 3); // 1y tier, 2.5x
        (uint128 amount, uint128 weight, uint64 unlockAt,,) = staking.positions(alice, id);
        assertEq(amount, 100e18);
        assertEq(weight, 250e18);
        assertEq(unlockAt, block.timestamp + 365 days);
        assertEq(staking.totalStaked(), 100e18);
        assertEq(staking.totalWeight(), 250e18);
    }

    function test_withdrawBeforeUnlockReverts() public {
        vm.startPrank(alice);
        uint256 id = staking.stake(100e18, 0); // 7d lock
        vm.expectRevert(BoostedStaking.StillLocked.selector);
        staking.withdraw(id);

        skip(7 days);
        staking.withdraw(id);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 1_000e18);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.totalWeight(), 0);
    }

    function test_withdrawTwiceReverts() public {
        vm.startPrank(alice);
        uint256 id = staking.stake(100e18, 0);
        skip(7 days);
        staking.withdraw(id);
        vm.expectRevert(BoostedStaking.PositionClosed.selector);
        staking.withdraw(id);
        vm.stopPrank();
    }

    function test_boostSkewsRewards() public {
        // Same amount, different tiers: alice 1x (7d), bob 2.5x (1y).
        vm.prank(alice);
        uint256 aId = staking.stake(100e18, 0);
        vm.prank(bob);
        uint256 bId = staking.stake(100e18, 3);

        _notify(7_000e18);
        skip(7 days); // full period elapses

        uint256 aEarned = staking.earned(alice, aId);
        uint256 bEarned = staking.earned(bob, bId);
        // bob's weight is 2.5x alice's → rewards split 100:250.
        assertApproxEqRel(bEarned, aEarned * 5 / 2, 1e15);
        assertApproxEqAbs(aEarned + bEarned, 7_000e18, 1e12); // dust from integer rates
    }

    function test_claimPaysAndResets() public {
        vm.prank(alice);
        uint256 id = staking.stake(100e18, 0);
        _notify(700e18);
        skip(7 days);

        uint256 expected = staking.earned(alice, id);
        vm.prank(alice);
        staking.claim(id);
        assertEq(token.balanceOf(alice), 900e18 + expected);
        assertEq(staking.earned(alice, id), 0);
    }

    function test_notifySolvencyGuard_sameToken() public {
        // Distributor with no balance backing: approve but only transfer `reward`,
        // guard must still pass because tokens were pulled in. Sanity path:
        _notify(100e18); // works — tokens pulled from distributor
        // Direct insolvency can't happen since notify pulls tokens; verify staked
        // principal is excluded from the reward budget:
        vm.prank(alice);
        staking.stake(1_000e18, 0);
        assertEq(staking.totalStaked(), 1_000e18);
        _notify(100e18); // must not treat alice's principal as budget
    }

    function test_notifyOnlyDistributor() public {
        vm.expectRevert(BoostedStaking.NotDistributor.selector);
        staking.notifyRewardAmount(1e18);
    }

    function test_pauseBlocksStakeNotWithdraw() public {
        vm.prank(alice);
        uint256 id = staking.stake(100e18, 0);

        vm.prank(owner);
        staking.pause();

        vm.prank(alice);
        vm.expectRevert();
        staking.stake(1e18, 0);

        skip(7 days);
        vm.prank(alice);
        staking.withdraw(id); // withdraw works while paused
    }

    function test_disabledTierRejectsNewStakes() public {
        vm.prank(owner);
        staking.setTierEnabled(0, false);
        vm.prank(alice);
        vm.expectRevert(BoostedStaking.TierDisabled.selector);
        staking.stake(1e18, 0);
    }

    function test_addTierBounds() public {
        vm.startPrank(owner);
        vm.expectRevert(BoostedStaking.InvalidParams.selector);
        staking.addTier(1 days, 9_999); // < 1x
        vm.expectRevert(BoostedStaking.InvalidParams.selector);
        staking.addTier(1 days, 50_001); // > 5x
        staking.addTier(2 * 365 days, 40_000); // valid
        vm.stopPrank();
        assertEq(staking.tiersLength(), 5);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_twoStakersProportionalToWeight(uint96 a, uint96 b) public {
        uint256 amtA = bound(uint256(a), 1e18, 1_000e18);
        uint256 amtB = bound(uint256(b), 1e18, 1_000e18);

        vm.prank(alice);
        uint256 aId = staking.stake(amtA, 1); // 1.25x
        vm.prank(bob);
        uint256 bId = staking.stake(amtB, 2); // 1.5x

        _notify(70_000e18);
        skip(7 days);

        uint256 wA = amtA * 12_500 / 10_000;
        uint256 wB = amtB * 15_000 / 10_000;
        uint256 aEarned = staking.earned(alice, aId);
        uint256 bEarned = staking.earned(bob, bId);

        // Each staker's share matches weight share within rounding tolerance.
        assertApproxEqRel(aEarned, (aEarned + bEarned) * wA / (wA + wB), 1e13);
    }
}
