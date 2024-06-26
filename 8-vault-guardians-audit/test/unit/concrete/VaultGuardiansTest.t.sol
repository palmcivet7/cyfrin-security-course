// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {VaultGuardians, IERC20} from "../../../src/protocol/VaultGuardians.sol";

contract VaultGuardiansTest is Base_Test {
    address user = makeAddr("user");

    uint256 mintAmount = 100 ether;

    function setUp() public override {
        Base_Test.setUp();
    }

    function testUpdateGuardianStakePrice() public {
        uint256 newStakePrice = 10;
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianStakePrice(newStakePrice);
        assertEq(vaultGuardians.getGuardianStakePrice(), newStakePrice);
    }

    function testUpdateGuardianStakePriceOnlyOwner() public {
        uint256 newStakePrice = 10;
        vm.prank(user);
        vm.expectRevert();
        vaultGuardians.updateGuardianStakePrice(newStakePrice);
    }

    function testUpdateGuardianAndDaoCut() public {
        uint256 newGuardianAndDaoCut = 10;
        vm.prank(vaultGuardians.owner());
        vaultGuardians.updateGuardianAndDaoCut(newGuardianAndDaoCut);
        assertEq(vaultGuardians.getGuardianAndDaoCut(), newGuardianAndDaoCut);
    }

    function testUpdateGuardianAndDaoCutOnlyOwner() public {
        uint256 newGuardianAndDaoCut = 10;
        vm.prank(user);
        vm.expectRevert();
        vaultGuardians.updateGuardianAndDaoCut(newGuardianAndDaoCut);
    }

    function testSweepErc20s() public {
        ERC20Mock mock = new ERC20Mock();
        mock.mint(mintAmount, msg.sender);
        vm.prank(msg.sender);
        mock.transfer(address(vaultGuardians), mintAmount);

        uint256 balanceBefore = mock.balanceOf(address(vaultGuardianGovernor));

        vm.prank(vaultGuardians.owner());
        vaultGuardians.sweepErc20s(IERC20(mock));

        uint256 balanceAfter = mock.balanceOf(address(vaultGuardianGovernor));

        assertEq(balanceAfter - balanceBefore, mintAmount);
    }

    event VaultGuardians__UpdatedStakePrice(uint256 oldStakePrice, uint256 newStakePrice);

    function test_VaultGuardians__UpdatedStakePrice_event_emits_new_price_twice() public {
        uint256 oldStakePrice = 9;
        uint256 newStakePrice = 10;
        vm.startPrank(vaultGuardians.owner());
        vaultGuardians.updateGuardianStakePrice(oldStakePrice);
        vm.expectEmit(address(vaultGuardians));
        emit VaultGuardians__UpdatedStakePrice(newStakePrice, newStakePrice);
        vaultGuardians.updateGuardianStakePrice(newStakePrice);
        vm.stopPrank();
    }

    function test_updateGuardianAndDaoCut_emits_wrong_event() public {
        uint256 newCut = 10;
        vm.startPrank(vaultGuardians.owner());
        vm.expectEmit(address(vaultGuardians));
        emit VaultGuardians__UpdatedStakePrice(newCut, newCut);
        vaultGuardians.updateGuardianAndDaoCut(newCut);
        vm.stopPrank();
    }
}
