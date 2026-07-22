// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseScript} from "./Base.s.sol";
import {RHVYToken} from "../src/token/RHVYToken.sol";
import {console} from "forge-std/console.sol";

/// @notice Deploys the launch utility token. During integration testing you can skip
///         this and keep `utilityToken` in robinhood.json pointed at the TEST token.
///
///         Env: TOKEN_NAME, TOKEN_SYMBOL, TREASURY
///         Run: forge script script/DeployToken.s.sol --rpc-url robinhood --broadcast
contract DeployToken is BaseScript {
    function run() external {
        string memory name = vm.envOr("TOKEN_NAME", string("RH Yield Vault Token"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("RHVY"));
        address treasury = vm.envAddress("TREASURY");

        vm.startBroadcast();
        RHVYToken token = new RHVYToken(name, symbol, treasury);
        vm.stopBroadcast();

        console.log("RHVYToken deployed:", address(token));
        console.log("Update script/config/robinhood.json `utilityToken` to this address.");
    }
}
