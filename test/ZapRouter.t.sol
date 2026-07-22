// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ZapRouter} from "../src/router/ZapRouter.sol";
import {MockERC20, MockVault, MockSwapRouter} from "./mocks/Mocks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ISwapRouterV3} from "../src/interfaces/ISwapRouterV3.sol";

contract ZapRouterTest is Test {
    MockERC20 usdg;
    MockERC20 usdc;
    MockVault vault;
    MockSwapRouter router;
    ZapRouter zap;
    address alice = makeAddr("alice");

    function setUp() public {
        usdg = new MockERC20("USDG", "USDG", 6);
        usdc = new MockERC20("USDC", "USDC", 6);
        vault = new MockVault(IERC20(usdg));
        router = new MockSwapRouter();
        zap = new ZapRouter(IERC4626(vault), ISwapRouterV3(router));

        usdg.mint(address(router), 1_000_000e6); // router liquidity
        usdc.mint(alice, 1_000e6);
        usdg.mint(alice, 1_000e6);
        vm.startPrank(alice);
        usdc.approve(address(zap), type(uint256).max);
        usdg.approve(address(zap), type(uint256).max);
        vm.stopPrank();
    }

    function test_zapWithSwap() public {
        vm.prank(alice);
        uint256 shares = zap.zapIn(IERC20(usdc), 100e6, 3000, 100e6, alice);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.convertToAssets(shares), 100e6); // 1:1 mock rate
        assertEq(usdc.balanceOf(address(zap)), 0);
        assertEq(usdg.balanceOf(address(zap)), 0);
    }

    function test_zapUsdgPassthroughSkipsSwap() public {
        vm.prank(alice);
        uint256 shares = zap.zapIn(IERC20(usdg), 250e6, 3000, 0, alice);
        assertEq(vault.convertToAssets(shares), 250e6);
    }

    function test_slippageRevertsBubbleUp() public {
        router.setRate(9, 10); // 10% haircut
        vm.prank(alice);
        vm.expectRevert("Too little received");
        zap.zapIn(IERC20(usdc), 100e6, 3000, 100e6, alice);
    }

    function test_zeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert(ZapRouter.ZeroAmount.selector);
        zap.zapIn(IERC20(usdc), 0, 3000, 0, alice);
    }

    function test_zeroReceiverReverts() public {
        vm.prank(alice);
        vm.expectRevert(ZapRouter.ZeroAddress.selector);
        zap.zapIn(IERC20(usdc), 1e6, 3000, 0, address(0));
    }
}
