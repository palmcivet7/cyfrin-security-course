// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { L1BossBridge } from "../../src/L1BossBridge.sol";
import { L1Token } from "../../src/L1Token.sol";
import { L1Vault } from "../../src/L1Vault.sol";
import { Handler } from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {
    L1Token token;
    L1BossBridge bridge;
    L1Vault vault;
    Handler handler;

    address owner = makeAddr("owner");

    uint256 public constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        vm.startPrank(owner);
        token = new L1Token();
        bridge = new L1BossBridge(token);
        vault = bridge.vault();

        deal(owner, STARTING_BALANCE);

        handler = new Handler(bridge, token, vault);
        deal(address(handler), STARTING_BALANCE);
        targetContract(address(handler));

        vm.stopPrank();
    }

    function test_initial_supply() public view {
        uint256 initialSupply = token.balanceOf(owner);
        console.log("initialSupply:", initialSupply);
    }

    function invariant_deposits_should_never_go_above_limit() public {
        uint256 depositLimit = 100_000 ether;
        uint256 vaultBalance = token.balanceOf(address(vault));
        assertGe(depositLimit, vaultBalance);
    }
}
