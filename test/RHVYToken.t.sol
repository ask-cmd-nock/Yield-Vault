// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RHVYToken} from "../src/token/RHVYToken.sol";

contract RHVYTokenTest is Test {
    RHVYToken token;
    address treasury = makeAddr("treasury");
    address alice;
    uint256 aliceKey;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        token = new RHVYToken("RH Yield Vault Token", "RHVY", treasury);
    }

    function test_fixedSupplyMintedToTreasury() public view {
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(treasury), 1_000_000_000e18);
    }

    function test_zeroTreasuryReverts() public {
        vm.expectRevert(RHVYToken.ZeroAddress.selector);
        new RHVYToken("x", "X", address(0));
    }

    function test_votesTrackDelegation() public {
        vm.prank(treasury);
        token.transfer(alice, 100e18);
        assertEq(token.getVotes(alice), 0); // no votes before self-delegation

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 100e18);

        vm.prank(alice);
        token.transfer(treasury, 40e18);
        assertEq(token.getVotes(alice), 60e18);
    }

    function test_permit() public {
        vm.prank(treasury);
        token.transfer(alice, 1e18);

        address spender = makeAddr("spender");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                alice,
                spender,
                1e18,
                token.nonces(alice),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        token.permit(alice, spender, 1e18, deadline, v, r, s);
        assertEq(token.allowance(alice, spender), 1e18);
    }
}
