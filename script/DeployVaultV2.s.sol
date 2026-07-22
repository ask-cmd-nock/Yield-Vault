// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseScript} from "./Base.s.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {IMorphoMarketV1AdapterV2Factory} from "../src/interfaces/IMorphoMarketV1AdapterV2.sol";
import {MarketParams} from "../src/interfaces/IMorphoTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {console} from "forge-std/console.sol";

/// @notice Deploys and wires the USDG Morpho Vault V2 on Robinhood Chain:
///           1. create the vault via the official VaultV2Factory,
///           2. create a MorphoMarketV1AdapterV2 for it,
///           3. add the adapter, set caps per market (adapter / collateral / market ids),
///           4. set performance fee + recipient, allocator, sentinel,
///           5. seed-deposit and burn shares (inflation-attack hardening),
///           6. raise timelocks on sensitive selectors and hand roles to production addresses.
///
///         Markets come from robinhood.json `markets` (see README for the format). All
///         curator calls go through submit() then direct execution, which works in one
///         tx while timelocks are still zero at deployment.
///
///         Env: OWNER, CURATOR, ALLOCATOR, SENTINEL, FEE_RECIPIENT (FeeCollectorBuyback),
///              PERF_FEE_WAD (default 0.15e18), SEED_AMOUNT (USDG wei, default 100e6), SALT
///         Run: forge script script/DeployVaultV2.s.sol --rpc-url robinhood --broadcast
contract DeployVaultV2 is BaseScript {
    using SafeERC20 for IERC20;

    // Field order must stay alphabetical: that is how vm.parseJson decodes JSON objects.
    struct JsonMarket {
        uint256 absoluteCap; // max USDG allocated to this market
        address collateralToken;
        uint256 collateralTokenAbsoluteCap; // max USDG across all markets sharing this collateral
        address irm;
        uint256 lltv;
        address loanToken;
        address oracle;
        uint256 relativeCapWad; // max share of vault TVL, WAD (1e18 = 100%)
    }

    IVaultV2 vault;

    function run() external {
        _loadConfig();
        address owner = vm.envAddress("OWNER");
        address curator = vm.envAddress("CURATOR");
        address allocator = vm.envAddress("ALLOCATOR");
        address sentinel = vm.envAddress("SENTINEL");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 perfFee = vm.envOr("PERF_FEE_WAD", uint256(0.15e18)); // 15%
        uint256 seedAmount = vm.envOr("SEED_AMOUNT", uint256(100e6)); // 100 USDG
        bytes32 salt = vm.envOr("SALT", bytes32(uint256(1)));

        require(perfFee <= 0.2e18, "fee above 20% policy cap");

        address usdg = _addr("usdg");
        IVaultV2Factory factory = IVaultV2Factory(_addr("vaultV2Factory"));
        IMorphoMarketV1AdapterV2Factory adapterFactory =
            IMorphoMarketV1AdapterV2Factory(_addr("morphoMarketV1AdapterV2Factory"));
        require(address(adapterFactory) != address(0), "set morphoMarketV1AdapterV2Factory in robinhood.json");

        vm.startBroadcast();

        // 1. Vault, owned by the deployer during wiring.
        vault = IVaultV2(factory.createVaultV2(msg.sender, usdg, salt));
        vault.setCurator(msg.sender);

        // 2. Morpho Market V1 adapter bound to this vault.
        address adapter = adapterFactory.createMorphoMarketV1AdapterV2(address(vault));

        // 3. Adapter + caps.
        _submitAndCall(abi.encodeCall(IVaultV2.addAdapter, (adapter)));

        // Whole-adapter exposure: uncapped relative (100%), generous absolute; per-market
        // and per-collateral ids below are the binding limits.
        bytes memory adapterIdData = abi.encode("this", adapter);
        _submitAndCall(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterIdData, type(uint128).max)));
        _submitAndCall(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterIdData, 1e18)));

        JsonMarket[] memory markets = abi.decode(vm.parseJson(config, ".markets"), (JsonMarket[]));
        for (uint256 i; i < markets.length; i++) {
            JsonMarket memory m = markets[i];
            require(m.loanToken == usdg, "market loan token must be USDG");
            MarketParams memory params = MarketParams({
                loanToken: m.loanToken,
                collateralToken: m.collateralToken,
                oracle: m.oracle,
                irm: m.irm,
                lltv: m.lltv
            });

            bytes memory collateralIdData = abi.encode("collateralToken", m.collateralToken);
            bytes memory marketIdData = abi.encode("this/marketParams", adapter, params);

            _submitAndCall(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (collateralIdData, m.collateralTokenAbsoluteCap)));
            _submitAndCall(abi.encodeCall(IVaultV2.increaseRelativeCap, (collateralIdData, m.relativeCapWad)));
            _submitAndCall(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (marketIdData, m.absoluteCap)));
            _submitAndCall(abi.encodeCall(IVaultV2.increaseRelativeCap, (marketIdData, m.relativeCapWad)));
        }

        // 4. Fees, allocator, sentinel.
        _submitAndCall(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (feeRecipient)));
        _submitAndCall(abi.encodeCall(IVaultV2.setPerformanceFee, (perfFee)));
        _submitAndCall(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        vault.setIsSentinel(sentinel, true);

        // 5. Seed deposit, shares parked at the dead address forever.
        if (seedAmount > 0) {
            IERC20(usdg).forceApprove(address(vault), seedAmount);
            vault.deposit(seedAmount, address(0xdEaD));
        }

        // 6. Timelocks on the riskiest curator actions, then hand over roles.
        _submitAndCall(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.increaseAbsoluteCap.selector, 2 days)));
        _submitAndCall(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.increaseRelativeCap.selector, 2 days)));
        _submitAndCall(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.addAdapter.selector, 2 days)));
        _submitAndCall(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.setPerformanceFee.selector, 2 days)));

        vault.setCurator(curator);
        vault.setOwner(owner);

        vm.stopBroadcast();

        console.log("VaultV2:  ", address(vault));
        console.log("Adapter:  ", adapter);
        console.log("Markets wired:", markets.length);
    }

    /// @dev Curator actions are timelocked behind submit(); with fresh-vault timelocks of
    ///      zero, submitting and executing in the same transaction succeeds.
    function _submitAndCall(bytes memory data) internal {
        vault.submit(data);
        (bool ok, bytes memory ret) = address(vault).call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}
