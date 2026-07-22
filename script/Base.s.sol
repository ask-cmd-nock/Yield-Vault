// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";

/// @notice Shared config loader. All chain addresses live in script/config/robinhood.json —
///         never hardcoded in contracts — because Robinhood Chain is full of impostor
///         tokens reusing official symbols.
abstract contract BaseScript is Script {
    string internal config;

    function _loadConfig() internal {
        config = vm.readFile(string.concat(vm.projectRoot(), "/script/config/robinhood.json"));
    }

    function _addr(string memory key) internal view returns (address) {
        return vm.parseJsonAddress(config, string.concat(".", key));
    }
}
