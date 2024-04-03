// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Base_Test} from "../../Base.t.sol";
import {console} from "forge-std/console.sol";
import {VaultShares} from "../../../src/protocol/VaultShares.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {VaultShares, IERC20} from "../../../src/protocol/VaultShares.sol";

import {console} from "forge-std/console.sol";

import {IVaultShares} from "../../../src/interfaces/IVaultShares.sol";

contract VaultSharesTest is Base_Test {
    uint256 mintAmount = 100 ether;
    address guardian = makeAddr("guardian");
    address user = makeAddr("user");
    AllocationData allocationData = AllocationData(
        500, // hold
        250, // uniswap
        250 // aave
    );
    VaultShares public wethVaultShares;
    uint256 public defaultGuardianAndDaoCut = 1000;

    AllocationData newAllocationData = AllocationData(
        0, // hold
        500, // uniswap
        500 // aave
    );

    function setUp() public override {
        Base_Test.setUp();
    }

    modifier hasGuardian() {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(allocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();
        _;
    }

    function testSetupVaultShares() public hasGuardian {
        assertEq(wethVaultShares.getGuardian(), guardian);
        assertEq(wethVaultShares.getGuardianAndDaoCut(), defaultGuardianAndDaoCut);
        assertEq(wethVaultShares.getVaultGuardians(), address(vaultGuardians));
        assertEq(wethVaultShares.getIsActive(), true);
        assertEq(wethVaultShares.getAaveAToken(), address(awethTokenMock));
        assertEq(
            address(wethVaultShares.getUniswapLiquidtyToken()), uniswapFactoryMock.getPair(address(weth), address(weth))
        );
    }

    function testSetNotActive() public hasGuardian {
        vm.prank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        assertEq(wethVaultShares.getIsActive(), false);
    }

    function testOnlyVaultGuardiansCanSetNotActive() public hasGuardian {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultShares.VaultShares__NotVaultGuardianContract.selector));
        wethVaultShares.setNotActive();
    }

    function testOnlyCanSetNotActiveIfActive() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        vm.expectRevert(abi.encodeWithSelector(VaultShares.VaultShares__NotActive.selector));
        wethVaultShares.setNotActive();
        vm.stopPrank();
    }

    function testUpdateHoldingAllocation() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.updateHoldingAllocation(newAllocationData);
        assertEq(wethVaultShares.getAllocationData().holdAllocation, newAllocationData.holdAllocation);
        assertEq(wethVaultShares.getAllocationData().uniswapAllocation, newAllocationData.uniswapAllocation);
        assertEq(wethVaultShares.getAllocationData().aaveAllocation, newAllocationData.aaveAllocation);
    }

    function testOnlyVaultGuardiansCanUpdateAllocationData() public hasGuardian {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultShares.VaultShares__NotVaultGuardianContract.selector));
        wethVaultShares.updateHoldingAllocation(newAllocationData);
    }

    function testOnlyupdateAllocationDataWhenActive() public hasGuardian {
        vm.startPrank(wethVaultShares.getVaultGuardians());
        wethVaultShares.setNotActive();
        vm.expectRevert(abi.encodeWithSelector(VaultShares.VaultShares__NotActive.selector));
        wethVaultShares.updateHoldingAllocation(newAllocationData);
        vm.stopPrank();
    }

    function testMustUpdateAllocationDataWithCorrectPrecision() public hasGuardian {
        AllocationData memory badAllocationData = AllocationData(0, 200, 500);
        uint256 totalBadAllocationData =
            badAllocationData.holdAllocation + badAllocationData.aaveAllocation + badAllocationData.uniswapAllocation;

        vm.startPrank(wethVaultShares.getVaultGuardians());
        vm.expectRevert(
            abi.encodeWithSelector(VaultShares.VaultShares__AllocationNot100Percent.selector, totalBadAllocationData)
        );
        wethVaultShares.updateHoldingAllocation(badAllocationData);
        vm.stopPrank();
    }

    function testUserCanDepositFunds() public hasGuardian {
        weth.mint(mintAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);

        assert(wethVaultShares.balanceOf(user) > 0);
    }

    function testUserDepositsFundsAndDaoAndGuardianGetShares() public hasGuardian {
        uint256 startingGuardianBalance = wethVaultShares.balanceOf(guardian);
        uint256 startingDaoBalance = wethVaultShares.balanceOf(address(vaultGuardians));

        weth.mint(mintAmount, user);
        vm.startPrank(user);
        console.log(wethVaultShares.totalSupply());
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);

        assert(wethVaultShares.balanceOf(guardian) > startingGuardianBalance);
        assert(wethVaultShares.balanceOf(address(vaultGuardians)) > startingDaoBalance);
    }

    modifier userIsInvested() {
        weth.mint(mintAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, user);
        vm.stopPrank();
        _;
    }

    function testRebalanceResultsInTheSameOutcome() public hasGuardian userIsInvested {
        uint256 startingUniswapLiquidityTokensBalance =
            IERC20(wethVaultShares.getUniswapLiquidtyToken()).balanceOf(address(wethVaultShares));
        uint256 startingAaveAtokensBalance = IERC20(wethVaultShares.getAaveAToken()).balanceOf(address(wethVaultShares));

        wethVaultShares.rebalanceFunds();

        assertEq(
            IERC20(wethVaultShares.getUniswapLiquidtyToken()).balanceOf(address(wethVaultShares)),
            startingUniswapLiquidityTokensBalance
        );
        assertEq(
            IERC20(wethVaultShares.getAaveAToken()).balanceOf(address(wethVaultShares)), startingAaveAtokensBalance
        );
    }

    function testWithdraw() public hasGuardian userIsInvested {
        uint256 startingBalance = weth.balanceOf(user);
        uint256 startingSharesBalance = wethVaultShares.balanceOf(user);
        uint256 amoutToWithdraw = 1 ether;

        vm.prank(user);
        wethVaultShares.withdraw(amoutToWithdraw, user, user);

        assertEq(weth.balanceOf(user), startingBalance + amoutToWithdraw);
        assert(wethVaultShares.balanceOf(user) < startingSharesBalance);
    }

    function testRedeem() public hasGuardian userIsInvested {
        uint256 startingBalance = weth.balanceOf(user);
        uint256 startingSharesBalance = wethVaultShares.balanceOf(user);
        uint256 amoutToRedeem = 1 ether;

        vm.prank(user);
        wethVaultShares.redeem(amoutToRedeem, user, user);

        assert(weth.balanceOf(user) > startingBalance);
        assertEq(wethVaultShares.balanceOf(user), startingSharesBalance - amoutToRedeem);
    }

    function test_link_vault_has_incorrect_name_and_symbol() public hasGuardian {
        address tokenTwoAddress = address(vaultGuardians.getTokenTwo());
        console.log("tokenTwoAddress:", tokenTwoAddress);
        console.log("linkAddress:", linkAddress);
        assertEq(tokenTwoAddress, linkAddress);

        // mint tokens to guardian
        link.mint(mintAmount, guardian);

        // create token vault
        vm.startPrank(guardian);
        link.approve(address(vaultGuardians), mintAmount);
        address linkVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, link);
        VaultShares linkVaultShares = VaultShares(linkVaultAddress);
        vm.stopPrank();

        string memory actualLinkVaultName = linkVaultShares.name();
        string memory actualLinkVaultSymbol = linkVaultShares.symbol();
        string memory expectedLinkVaultName = vaultGuardians.TOKEN_TWO_VAULT_NAME();
        string memory expectedLinkVaultSymbol = vaultGuardians.TOKEN_TWO_VAULT_SYMBOL();
        console.log("actualLinkVaultName:", actualLinkVaultName);
        console.log("actualLinkVaultSymbol:", actualLinkVaultSymbol);
        console.log("expectedLinkVaultName:", expectedLinkVaultName);
        console.log("expectedLinkVaultSymbol:", expectedLinkVaultSymbol);
        assert(keccak256(abi.encodePacked(actualLinkVaultName)) != keccak256(abi.encodePacked(expectedLinkVaultName)));
        assert(
            keccak256(abi.encodePacked(actualLinkVaultSymbol)) != keccak256(abi.encodePacked(expectedLinkVaultSymbol))
        );
    }

    function test_deposit_receiver_breaks() public hasGuardian {
        address attacker = makeAddr("attacker");

        // mint tokens to users
        usdc.mint(mintAmount, guardian);
        usdc.mint(mintAmount, attacker);
        usdc.mint(mintAmount, user);

        // create token vault
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address tokenVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        VaultShares vault = VaultShares(tokenVaultAddress);
        vm.stopPrank();

        vm.startPrank(attacker);
        usdc.approve(tokenVaultAddress, mintAmount);
        vault.deposit(mintAmount, address(vaultGuardianGovernor));
        vm.stopPrank();

        vm.startPrank(guardian);
        vault.approve(address(vaultGuardians), type(uint256).max);
        vaultGuardians.quitGuardian(IERC20(usdc));
    }

    function test_sweepErc20s_lacks_access_control() public hasGuardian userIsInvested {
        uint256 sharesBalance = wethVaultShares.balanceOf(address(vaultGuardians));
        console.log("sharesBalance before:", sharesBalance);

        vaultGuardians.sweepErc20s(wethVaultShares);

        uint256 sharesBalanceAfter = wethVaultShares.balanceOf(address(vaultGuardians));
        console.log("sharesBalanceAfter:", sharesBalanceAfter);

        assertGt(sharesBalance, sharesBalanceAfter);
    }

    function test_share_dilution() public hasGuardian {
        // Setup: Mint and approve WETH for deposit by a user.
        uint256 depositAmount = 10 ether;
        weth.mint(depositAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), depositAmount);

        // Capture pre-deposit state
        uint256 totalSharesBeforeDeposit = wethVaultShares.totalSupply();
        uint256 guardianSharesBefore = wethVaultShares.balanceOf(guardian);
        uint256 vaultGuardianSharesBefore = wethVaultShares.balanceOf(address(vaultGuardians));

        // Perform deposit
        uint256 userShares = wethVaultShares.deposit(depositAmount, user);

        // Capture post-deposit state
        uint256 totalSharesAfterDeposit = wethVaultShares.totalSupply();
        uint256 guardianSharesAfter = wethVaultShares.balanceOf(guardian);
        uint256 vaultGuardianSharesAfter = wethVaultShares.balanceOf(address(vaultGuardians));

        // Calculate the shares minted for guardian and vault guardians
        uint256 sharesMintedForGuardian = guardianSharesAfter - guardianSharesBefore;
        uint256 sharesMintedForVaultGuardians = vaultGuardianSharesAfter - vaultGuardianSharesBefore;

        // Asserts to demonstrate the finding
        assertGt(totalSharesAfterDeposit, totalSharesBeforeDeposit + userShares);
        assertTrue(sharesMintedForGuardian > 0);
        assertTrue(sharesMintedForVaultGuardians > 0);
        assertEq(
            totalSharesAfterDeposit,
            totalSharesBeforeDeposit + userShares + sharesMintedForGuardian + sharesMintedForVaultGuardians
        );

        vm.stopPrank();
    }

    // function getVaultFromGuardianAndToken(address guardian, IERC20 token) external view returns (IVaultShares) {
    //     return s_guardians[guardian][token];
    // }

    function test_guardian_creates_new_vault() public hasGuardian userIsInvested {
        IVaultShares firstVault = vaultGuardians.getVaultFromGuardianAndToken(guardian, weth);

        // new vault
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault2 = vaultGuardians.becomeGuardian(allocationData);
        VaultShares wethVaultShares2 = VaultShares(wethVault2);
        vm.stopPrank();

        IVaultShares secondVault = vaultGuardians.getVaultFromGuardianAndToken(guardian, weth);

        assert(firstVault != secondVault);

        // guardian quits second vault
        vm.startPrank(guardian);
        wethVaultShares2.approve(address(vaultGuardians), type(uint256).max);
        vaultGuardians.quitGuardian();
        vm.stopPrank();

        IVaultShares noVault = vaultGuardians.getVaultFromGuardianAndToken(guardian, weth);
        console.log("noVault:", address(noVault));

        assertEq(address(noVault), address(0));

        // users can still interact with first vault
        vm.prank(user);
        wethVaultShares.withdraw(1, user, user);
    }

    AllocationData heldAllocationData = AllocationData(
        1000, // hold
        0, // uniswap
        0 // aave
    );

    function testGuardianQuitRedeemsCorrectly() public {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVault = vaultGuardians.becomeGuardian(heldAllocationData);
        wethVaultShares = VaultShares(wethVault);
        vm.stopPrank();

        uint256 vaultAssetsBeforeDeposit = wethVaultShares.totalAssets();

        // Step 1: Setup initial deposit from a user to ensure the vault has assets
        uint256 userDepositAmount = 5 ether;
        weth.mint(userDepositAmount, user);
        vm.startPrank(user);
        weth.approve(address(wethVaultShares), userDepositAmount);
        wethVaultShares.deposit(userDepositAmount, user);
        // uint256 userSharesAfterDeposit = wethVaultShares.balanceOf(user);
        assertEq(wethVaultShares.totalAssets(), userDepositAmount + vaultAssetsBeforeDeposit);
        vm.stopPrank();

        // Step 2: Guardian decides to quit - triggering redemption of their shares
        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), type(uint256).max);
        uint256 guardianAssetsBeforeQuitting = weth.balanceOf(guardian);
        vaultGuardians.quitGuardian();
        uint256 guardianAssetsAfterQuitting = weth.balanceOf(guardian);

        // Validate that the guardian received the correct amount of underlying assets for their shares
        assertTrue(guardianAssetsAfterQuitting > guardianAssetsBeforeQuitting);

        // Step 3: Validate vault state post-guardian quitting
        // This could involve checking total assets, total shares, or any other relevant metrics to ensure consistency
        uint256 remainingAssets = wethVaultShares.totalAssets();
        assertEq(
            remainingAssets,
            (userDepositAmount + vaultAssetsBeforeDeposit)
                - (guardianAssetsAfterQuitting - guardianAssetsBeforeQuitting)
        );
        // assertTrue(wethVaultShares.totalSupply() < userSharesAfterDeposit);
        vm.stopPrank();
        console.log("remainingAssets", remainingAssets);

        vm.prank(user);
        // wethVaultShares.maxRedeem(user)
        wethVaultShares.withdraw(4996668887408394404, user, user); // 4996668887408394404

        uint256 assetsAfterUserWithdraws = wethVaultShares.totalAssets();
        console.log("assetsAfterUserWithdraws", assetsAfterUserWithdraws);
    }

    function test_attacker_can_withdraw_other_users_funds() public hasGuardian userIsInvested {
        address attacker = makeAddr("attacker");

        // vm.prank(user);
        // wethVaultSha

        vm.startPrank(attacker);
        wethVaultShares.withdraw(1 ether, attacker, user);
        vm.stopPrank();
    }

    function test_cant_withdraw() public hasGuardian userIsInvested {
        vm.prank(user);
        vm.expectRevert();
        wethVaultShares.withdraw(mintAmount, user, user);
        // link.mint(mintAmount, guardian);
        // vm.startPrank(guardian);
        // link.approve(address(vaultGuardians), mintAmount);
        // address linkVault = vaultGuardians.becomeGuardian(allocationData);
        // VaultShares linkVaultShares = VaultShares(linkVault);
        // vm.stopPrank();

        // link.mint(mintAmount, user);
        // vm.startPrank(user);
        // link.approve(address(linkVaultShares), mintAmount);
        // linkVaultShares.deposit(mintAmount, user);
        // linkVaultShares.withdraw(mintAmount, user, user);
        // vm.stopPrank();
    }

    // // doesnt work because it reverts because weth is not tokenOne or tokenTwo
    // function test_becomeTokenGuardian_with_weth_address() public hasGuardian {
    //     // address wethAddress = address(vaultGuardians.getWeth());
    //     // console.log("tokenTwoAddress:", wethAddress);
    //     console.log("wethAddress:", wethAddress);
    //     // assertEq(tokenTwoAddress, linkAddress);

    //     assertEq(vaultGuardians.isApprovedToken(wethAddress), true);

    //     // mint tokens to guardian
    //     weth.mint(mintAmount, guardian);

    //     // create token vault
    //     vm.startPrank(guardian);
    //     weth.approve(address(vaultGuardians), mintAmount);
    //     address wethVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, weth);
    //     VaultShares wethVaultShares = VaultShares(wethVaultAddress);
    //     vm.stopPrank();
    // }

    // doesnt work because vault is funded with initial amount when created by guardian
    function test_erc4626_inflation_attack() public hasGuardian {
        // create attacker address
        address attacker = makeAddr("attacker");

        // mint tokens to users
        usdc.mint(mintAmount, guardian);
        usdc.mint(mintAmount, attacker);
        usdc.mint(mintAmount, user);

        // create token vault
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address tokenVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, usdc);
        VaultShares tokenVaultShares = VaultShares(tokenVaultAddress);
        vm.stopPrank();

        uint256 totalAssetsBeforeInit = tokenVaultShares.totalAssets();
        uint256 totalSupplyBeforeInit = tokenVaultShares.totalSupply();
        console.log("totalAssetsBeforeInit:", totalAssetsBeforeInit);
        console.log("totalSupplyBeforeInit:", totalSupplyBeforeInit);

        // attacker deposits
        vm.startPrank(attacker);
        usdc.approve(address(tokenVaultShares), 1);
        tokenVaultShares.deposit(1, attacker);

        uint256 totalAssetsBefore = tokenVaultShares.totalAssets();
        uint256 totalSupplyBefore = tokenVaultShares.totalSupply();
        console.log("totalAssetsBefore:", totalAssetsBefore);
        console.log("totalSupplyBefore:", totalSupplyBefore);

        // attacker transfers underlying token directly to vault
        usdc.transfer(address(tokenVaultShares), mintAmount - 1);
        vm.stopPrank();

        uint256 totalAssetsAfter = tokenVaultShares.totalAssets();
        uint256 totalSupplyAfter = tokenVaultShares.totalSupply();
        console.log("totalAssetsAfter:", totalAssetsAfter);
        console.log("totalSupplyAfter:", totalSupplyAfter);

        assertLt(totalAssetsBefore, totalAssetsAfter);
        assertEq(totalSupplyBefore, totalSupplyAfter);

        // user deposits
        vm.startPrank(user);
        usdc.approve(address(tokenVaultShares), mintAmount);
        tokenVaultShares.deposit(mintAmount, user);
        vm.stopPrank();

        uint256 attackerSharesBalance = tokenVaultShares.balanceOf(attacker);
        uint256 victimSharesBalance = tokenVaultShares.balanceOf(user);
        console.log("attackerSharesBalance:", attackerSharesBalance);
        console.log("victimSharesBalance:", victimSharesBalance);
    }

    // function test_share_holder_tranfers_to_zero_address() public hasGuardian {
    //     address attacker = makeAddr("attacker");
    //     address victim = makeAddr("victim");

    //     // mint tokens to users
    //     link.mint(mintAmount, guardian);
    //     link.mint(mintAmount, attacker);
    //     link.mint(mintAmount, victim);

    //     // create token vault
    //     vm.startPrank(guardian);
    //     link.approve(address(vaultGuardians), mintAmount);
    //     address tokenVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, link);
    //     VaultShares tokenVaultShares = VaultShares(tokenVaultAddress);
    //     vm.stopPrank();

    //     vm.startPrank(attacker);
    //     link.approve(tokenVaultAddress, mintAmount);
    //     tokenVaultShares.deposit(mintAmount, attacker);
    //     vm.stopPrank();

    //     vm.startPrank(victim);
    //     link.approve(tokenVaultAddress, mintAmount);
    //     tokenVaultShares.deposit(mintAmount, victim);
    //     vm.stopPrank();

    //     // check attacker and victim balances here
    //     uint256 userBalance = tokenVaultShares.balanceOf(attacker);
    //     uint256 userBalance2 = tokenVaultShares.balanceOf(victim);
    //     console.log("userBalance:", userBalance);
    //     console.log("userBalance2:", userBalance2);

    //     vm.startPrank(guardian);
    //     address owner = tokenVaultShares.owner();
    // }

    function test_receiver_DoS() public hasGuardian userIsInvested {
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);
        Receiver receiverContract = new Receiver();

        weth.mint(mintAmount, attacker);

        vm.startPrank(attacker);
        weth.approve(address(wethVaultShares), mintAmount);
        wethVaultShares.deposit(mintAmount, address(receiverContract));
        vm.stopPrank();

        vm.startPrank(guardian);
        wethVaultShares.approve(address(vaultGuardians), type(uint256).max);
        vaultGuardians.quitGuardian();
        vm.stopPrank();
    }
}

contract Receiver {}
