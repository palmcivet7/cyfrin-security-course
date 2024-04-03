// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {VaultGuardians} from "../../src/protocol/VaultGuardians.sol";
import {VaultGuardianToken} from "../../src/dao/VaultGuardianToken.sol";
import {VaultGuardianGovernor} from "../../src/dao/VaultGuardianGovernor.sol";
import {NetworkConfig} from "../../script/NetworkConfig.s.sol";
import {DeployVaultGuardians} from "../../script/DeployVaultGuardians.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {IVaultData} from "../../src/interfaces/IVaultData.sol";
import {UniswapRouterMock} from "../mocks/UniswapRouterMock.sol";
import {UniswapFactoryMock} from "../mocks/UniswapFactoryMock.sol";
import {AavePoolMock} from "../mocks/AavePoolMock.sol";

contract Invariant is StdInvariant, Test, IVaultData {
    Handler handler;

    VaultGuardians public vaultGuardians;
    VaultGuardianGovernor public vaultGuardianGovernor;
    VaultGuardianToken public vaultGuardianToken;
    NetworkConfig public networkConfig;
    address public aavePool;
    address public uniswapRouter;
    address public wethAddress;
    address public usdcAddress;
    address public linkAddress;
    ERC20Mock public weth;
    ERC20Mock public usdc;
    ERC20Mock public link;
    ERC20Mock public awethTokenMock;
    ERC20Mock public ausdcTokenMock;
    ERC20Mock public alinkTokenMock;
    UniswapFactoryMock public uniswapFactoryMock;
    DeployVaultGuardians public deployer;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        deployer = new DeployVaultGuardians();
        (vaultGuardians, vaultGuardianGovernor, vaultGuardianToken, networkConfig) = deployer.run();

        (aavePool, uniswapRouter, wethAddress, usdcAddress, linkAddress) = networkConfig.activeNetworkConfig();
        weth = ERC20Mock(wethAddress);
        usdc = ERC20Mock(usdcAddress);
        link = ERC20Mock(linkAddress);
        uniswapFactoryMock = UniswapFactoryMock(UniswapRouterMock(uniswapRouter).factory());

        _setupMocks();
        _labelContracts();

        handler = new Handler(
            address(vaultGuardians),
            payable(address(vaultGuardianGovernor)),
            address(vaultGuardianToken),
            aavePool,
            uniswapRouter,
            address(weth),
            address(usdc),
            address(link),
            address(awethTokenMock),
            address(ausdcTokenMock),
            address(alinkTokenMock),
            address(uniswapFactoryMock)
        );
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.withdraw.selector;
        // selectors[2] = Handler.quitGuardianWethVault.selector;
        // // selectors[3] = Handler.approve_shitcoin.selector;
        // // selectors[4] = Handler.transferFromShitcoin.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function _setupMocks() internal {
        if (block.chainid != 1) {
            uniswapFactoryMock.updatePairToReturn(uniswapRouter);
            awethTokenMock = new ERC20Mock();
            ausdcTokenMock = new ERC20Mock();
            alinkTokenMock = new ERC20Mock();
            AavePoolMock(aavePool).updateAtokenAddress(wethAddress, address(awethTokenMock));
            AavePoolMock(aavePool).updateAtokenAddress(usdcAddress, address(ausdcTokenMock));
            AavePoolMock(aavePool).updateAtokenAddress(linkAddress, address(alinkTokenMock));

            vm.label({account: address(awethTokenMock), newLabel: "aWETH"});
            vm.label({account: address(ausdcTokenMock), newLabel: "aUSDC"});
            vm.label({account: address(alinkTokenMock), newLabel: "aLINK"});
        }
    }

    function _labelContracts() internal {
        vm.label({account: wethAddress, newLabel: weth.name()});
        vm.label({account: usdcAddress, newLabel: usdc.name()});
        vm.label({account: linkAddress, newLabel: link.name()});
        vm.label({account: address(vaultGuardians), newLabel: "Vault Guardians"});
        vm.label({account: address(vaultGuardianGovernor), newLabel: "Vault Guardians Governor"});
        vm.label({account: address(vaultGuardianToken), newLabel: "Vault Guardians Token"});
        vm.label({account: address(uniswapRouter), newLabel: "Uniswap Router & Liquidity Token"});
        vm.label({account: address(uniswapFactoryMock), newLabel: "Uniswap Factory"});
    }

    function invariant_test_setup() public {}

    function invariant_test_depositors_can_withdraw() public {
        assertEq(handler.wethTotalDeposits(), handler.getWethVaultTotalAssets());
    }
}
