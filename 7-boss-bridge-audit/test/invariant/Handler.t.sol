// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { L1BossBridge } from "../../src/L1BossBridge.sol";
import { L1Token } from "../../src/L1Token.sol";
import { L1Vault } from "../../src/L1Vault.sol";

contract Handler is Test {
    L1Token token;
    L1BossBridge bridge;
    L1Vault vault;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 public constant ONE_THOUSAND_ETH = 1000 ether;
    uint256 public constant DEPOSIT_LIMIT = 100_000 ether;

    uint256 public ghostDeposits;

    constructor(L1BossBridge _bridge, L1Token _token, L1Vault _vault) {
        bridge = _bridge;
        token = _token;
        vault = _vault;
    }

    function depositTokensToL2(uint256 _msgSender, uint256 _from, uint256 _l2Recipient, uint256 _amount) public {
        uint256 currentVaultBalance = token.balanceOf(address(vault));
        uint256 maxAllowedDeposit = DEPOSIT_LIMIT > currentVaultBalance ? DEPOSIT_LIMIT - currentVaultBalance : 0;

        if (maxAllowedDeposit == 0) {
            // Deposit limit reached, so return early
            console.log("Deposit limit reached. No deposit made.");
            return;
        }

        // Ensure _amount does not exceed maxAllowedDeposit
        _amount = bound(_amount, 1, maxAllowedDeposit);

        address msgSender = _seedToAddress(_msgSender);
        address from = _seedToAddress(_from);
        address l2Recipient = _seedToAddress(_l2Recipient);

        console.log("msgSender:", msgSender);
        console.log("from:", from);
        console.log("l2Recipient:", l2Recipient);

        // Transfer tokens from the owner to the 'from' address
        vm.startPrank(owner);
        token.transfer(from, _amount);
        vm.stopPrank();

        // Approve the bridge to spend tokens on behalf of 'from'
        vm.startPrank(from);
        token.approve(address(bridge), _amount);
        vm.stopPrank();

        // Attempt the deposit
        vm.prank(msgSender);
        bridge.depositTokensToL2(from, l2Recipient, _amount);
        ghostDeposits += _amount;

        console.log("ghostDeposits:", ghostDeposits);
    }

    // utils
    function _seedToAddress(uint256 _addressSeed) internal pure returns (address) {
        return address(uint160(bound(_addressSeed, 1, type(uint160).max)));
    }
}
