// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseScript} from "./Base.s.sol";
import {BoostedStaking} from "../src/staking/BoostedStaking.sol";
import {FeeCollectorBuyback} from "../src/fees/FeeCollectorBuyback.sol";
import {ZapRouter} from "../src/router/ZapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ISwapRouterV3} from "../src/interfaces/ISwapRouterV3.sol";
import {console} from "forge-std/console.sol";

/// @notice Deploys BoostedStaking + FeeCollectorBuyback + ZapRouter and wires them.
///         Requires the Vault V2 to exist already (DeployVaultV2) and robinhood.json
///         `utilityToken` and `swapRouter` to be set.
///
///         Env: VAULT (vault address), TREASURY, OWNER (final admin, e.g. timelock/multisig)
///         Run: forge script script/DeployPeriphery.s.sol --rpc-url robinhood --broadcast
contract DeployPeriphery is BaseScript {
    function run() external {
        _loadConfig();
        address vault = vm.envAddress("VAULT");
        address treasury = vm.envAddress("TREASURY");
        address finalOwner = vm.envAddress("OWNER");
        IERC20 utilityToken = IERC20(_addr("utilityToken"));
        ISwapRouterV3 swapRouter = ISwapRouterV3(_addr("swapRouter"));
        require(address(swapRouter) != address(0), "set swapRouter in robinhood.json");

        vm.startBroadcast();

        // Deployer holds ownership during wiring, then hands over.
        BoostedStaking staking = new BoostedStaking(utilityToken, utilityToken, msg.sender);
        FeeCollectorBuyback collector =
            new FeeCollectorBuyback(IERC4626(vault), utilityToken, swapRouter, treasury, msg.sender);
        ZapRouter zap = new ZapRouter(IERC4626(vault), swapRouter);

        staking.setDistributor(address(collector));
        collector.setStaking(address(staking));

        staking.transferOwnership(finalOwner); // Ownable2Step: finalOwner must accept
        collector.transferOwnership(finalOwner);

        vm.stopBroadcast();

        console.log("BoostedStaking:      ", address(staking));
        console.log("FeeCollectorBuyback: ", address(collector));
        console.log("ZapRouter:           ", address(zap));
        console.log("NOTE: finalOwner must call acceptOwnership() on staking + collector,");
        console.log("      and the vault curator must set the collector as performanceFeeRecipient.");
    }
}
