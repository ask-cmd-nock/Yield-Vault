// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeCollectorBuyback} from "../src/fees/FeeCollectorBuyback.sol";
import {BoostedStaking} from "../src/staking/BoostedStaking.sol";
import {MockERC20, MockVault, MockSwapRouter} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ISwapRouterV3} from "../src/interfaces/ISwapRouterV3.sol";

contract FeeCollectorBuybackTest is Test {
    MockERC20 usdg;
    MockERC20 rhvy;
    MockVault vault;
    MockSwapRouter router;
    BoostedStaking staking;
    FeeCollectorBuyback collector;

    address owner = makeAddr("owner");
    address treasury = makeAddr("treasury");
    address keeper = makeAddr("keeper");
    address depositor = makeAddr("depositor");

    function setUp() public {
        // Foundry's clock starts at 1; move past minInterval like a real chain.
        vm.warp(30 days);
        usdg = new MockERC20("USDG", "USDG", 6);
        rhvy = new MockERC20("test", "TEST", 18);
        vault = new MockVault(IERC20(usdg));
        router = new MockSwapRouter();
        staking = new BoostedStaking(IERC20(rhvy), IERC20(rhvy), owner);
        collector = new FeeCollectorBuyback(
            IERC4626(vault), IERC20(rhvy), ISwapRouterV3(router), treasury, owner
        );

        vm.startPrank(owner);
        collector.setStaking(address(staking));
        collector.setKeeper(keeper, true);
        staking.setDistributor(address(collector));
        vm.stopPrank();

        // Router is funded with utility tokens; 1 USDG (1e6) buys 1e18 TEST via rate.
        rhvy.mint(address(router), 1_000_000e18);
        router.setRate(1e12, 1);

        // Simulate accrued performance fees: the collector holds vault shares.
        usdg.mint(depositor, 100_000e6);
        vm.startPrank(depositor);
        usdg.approve(address(vault), type(uint256).max);
        vault.deposit(100_000e6, address(collector));
        vm.stopPrank();
    }

    function test_executeSplitsCorrectly() public {
        vm.prank(keeper);
        collector.execute(1); // minOut sanity value; mock rate is deterministic

        uint256 harvested = 100_000e6;
        uint256 incentive = harvested * 10 / 10_000; // 0.10%
        uint256 remaining = harvested - incentive;
        uint256 buyAmount = remaining * 5_000 / 10_000;
        uint256 bought = buyAmount * 1e12;
        uint256 burned = bought * 2_000 / 10_000;
        uint256 toStakers = bought - burned;
        uint256 toTreasury = remaining - buyAmount;

        assertEq(usdg.balanceOf(keeper), incentive, "caller incentive");
        assertEq(usdg.balanceOf(treasury), toTreasury, "treasury USDG");
        assertEq(rhvy.balanceOf(collector.BURN_ADDRESS()), burned, "burned");
        assertEq(rhvy.balanceOf(address(staking)), toStakers, "staker rewards");
        assertEq(vault.balanceOf(address(collector)), 0, "all shares redeemed");
        assertEq(usdg.balanceOf(address(collector)), 0, "no USDG left behind");
    }

    function test_slippageGuardReverts() public {
        vm.prank(keeper);
        vm.expectRevert("Too little received");
        collector.execute(type(uint256).max);
    }

    function test_minOutZeroReverts() public {
        vm.prank(keeper);
        vm.expectRevert(FeeCollectorBuyback.MinOutZero.selector);
        collector.execute(0);
    }

    function test_nonKeeperReverts() public {
        vm.prank(depositor);
        vm.expectRevert(FeeCollectorBuyback.NotKeeper.selector);
        collector.execute(1);
    }

    function test_rateLimit() public {
        vm.startPrank(keeper);
        collector.execute(1);

        // Re-arm with more fee shares, then try again too soon.
        vm.stopPrank();
        usdg.mint(depositor, 10e6);
        vm.startPrank(depositor);
        vault.deposit(10e6, address(collector));
        vm.stopPrank();

        vm.startPrank(keeper);
        vm.expectRevert(FeeCollectorBuyback.TooSoon.selector);
        collector.execute(1);

        skip(6 hours);
        collector.execute(1); // works after the interval
        vm.stopPrank();
    }

    function test_nothingToExecuteReverts() public {
        vm.prank(keeper);
        collector.execute(1);
        skip(6 hours);
        vm.prank(keeper);
        vm.expectRevert(FeeCollectorBuyback.NothingToExecute.selector);
        collector.execute(1);
    }

    function test_noStakingRoutesToTreasury() public {
        vm.prank(owner);
        collector.setStaking(address(0));

        vm.prank(keeper);
        collector.execute(1);
        assertGt(rhvy.balanceOf(treasury), 0, "staker share parked at treasury");
        assertEq(rhvy.balanceOf(address(staking)), 0);
    }

    function test_pauseBlocksExecute() public {
        vm.prank(owner);
        collector.pause();
        vm.prank(keeper);
        vm.expectRevert();
        collector.execute(1);
    }

    function test_paramBounds() public {
        vm.startPrank(owner);
        vm.expectRevert(FeeCollectorBuyback.InvalidParams.selector);
        collector.setParams(10_001, 0, 0, 3000, 1 hours); // buyback > 100%
        vm.expectRevert(FeeCollectorBuyback.InvalidParams.selector);
        collector.setParams(5_000, 0, 101, 3000, 1 hours); // incentive > 1%
        collector.setParams(8_000, 5_000, 50, 500, 1 days); // valid
        vm.stopPrank();
        assertEq(collector.buybackBps(), 8_000);
    }

    function test_rescue() public {
        MockERC20 stray = new MockERC20("stray", "STR", 18);
        stray.mint(address(collector), 5e18);
        vm.prank(owner);
        collector.rescue(IERC20(stray), treasury, 5e18);
        assertEq(stray.balanceOf(treasury), 5e18);
    }
}
