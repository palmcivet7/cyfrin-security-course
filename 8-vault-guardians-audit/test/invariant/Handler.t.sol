// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VaultGuardians} from "../../src/protocol/VaultGuardians.sol";
import {VaultGuardianToken} from "../../src/dao/VaultGuardianToken.sol";
import {VaultGuardianGovernor} from "../../src/dao/VaultGuardianGovernor.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {UniswapRouterMock} from "../mocks/UniswapRouterMock.sol";
import {UniswapFactoryMock} from "../mocks/UniswapFactoryMock.sol";
import {AavePoolMock} from "../mocks/AavePoolMock.sol";
import {IVaultData} from "../../../src/interfaces/IVaultData.sol";
import {VaultShares, IERC20} from "../../../src/protocol/VaultShares.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Handler is Test, IVaultData {
    using EnumerableSet for EnumerableSet.AddressSet;

    VaultGuardians public vaultGuardians;
    VaultGuardianGovernor public vaultGuardianGovernor;
    VaultGuardianToken public vaultGuardianToken;
    AavePoolMock public aavePool;
    UniswapRouterMock public uniswapRouter;
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
    VaultShares public wethVaultShares;

    uint256 constant ONE_MILLION_TOKENS = 1_000_000 ether;

    uint256 mintAmount = 100 ether;
    AllocationData allocationData = AllocationData(
        500, // hold
        250, // uniswap
        250 // aave
    );

    EnumerableSet.AddressSet internal guardians;
    EnumerableSet.AddressSet internal wethVaults;
    EnumerableSet.AddressSet internal usdcVaults;
    EnumerableSet.AddressSet internal linkVaults;
    mapping(address => address) public guardiansToWethVaults;
    mapping(address => address) public guardiansToUsdcVaults;
    mapping(address => address) public guardiansToLinkVaults;
    mapping(address => address) public depositorsToVaults;

    address guardian = makeAddr("guardian");
    VaultShares public wethVault;
    VaultShares public usdcVault;
    VaultShares public linkVault;

    EnumerableSet.AddressSet internal depositors;
    mapping(address => mapping(VaultShares => uint256)) internal depositorsToVaultsToAmounts;
    uint256 public wethTotalDeposits;
    uint256 public usdcTotalDeposits;
    uint256 public linkTotalDeposits;

    constructor(
        address _vaultGuardians,
        address payable _vaultGuardianGovernor,
        address _vaultGuardianToken,
        address _aavePool,
        address _uniswapRouter,
        address _weth,
        address _usdc,
        address _link,
        address _awethTokenMock,
        address _ausdcTokenMock,
        address _alinkTokenMock,
        address _uniswapFactoryMock
    ) {
        vaultGuardians = VaultGuardians(_vaultGuardians);
        vaultGuardianGovernor = VaultGuardianGovernor(_vaultGuardianGovernor);
        vaultGuardianToken = VaultGuardianToken(_vaultGuardianToken);
        aavePool = AavePoolMock(_aavePool);
        uniswapRouter = UniswapRouterMock(_uniswapRouter);
        weth = ERC20Mock(_weth);
        usdc = ERC20Mock(_usdc);
        link = ERC20Mock(_link);
        awethTokenMock = ERC20Mock(_awethTokenMock);
        ausdcTokenMock = ERC20Mock(_ausdcTokenMock);
        alinkTokenMock = ERC20Mock(_alinkTokenMock);
        uniswapFactoryMock = UniswapFactoryMock(_uniswapFactoryMock);

        _becomeGuardian();
        _becomeTokenGuardian();
    }

    function _becomeGuardian() internal {
        weth.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        weth.approve(address(vaultGuardians), mintAmount);
        address wethVaultAddress = vaultGuardians.becomeGuardian(allocationData);
        wethVault = VaultShares(wethVaultAddress);
        vm.stopPrank();
    }

    function _becomeTokenGuardian() internal {
        usdc.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        usdc.approve(address(vaultGuardians), mintAmount);
        address usdcVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, IERC20(usdc));
        usdcVault = VaultShares(usdcVaultAddress);
        vm.stopPrank();

        link.mint(mintAmount, guardian);
        vm.startPrank(guardian);
        link.approve(address(vaultGuardians), mintAmount);
        address linkVaultAddress = vaultGuardians.becomeTokenGuardian(allocationData, IERC20(link));
        linkVault = VaultShares(linkVaultAddress);
        vm.stopPrank();
    }

    function deposit(uint256 _addressSeed, uint256 _amount, uint256 _vaultSeed) public {
        address user = _seedToAddress(_addressSeed);
        depositors.add(user);

        _amount = bound(_amount, 1, ONE_MILLION_TOKENS);

        if (_vaultSeed % 3 == 0) {
            weth.mint(_amount, user);

            vm.startPrank(user);
            weth.approve(address(wethVault), _amount);
            wethVault.deposit(_amount, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][wethVault] += _amount;
            wethTotalDeposits += _amount;
        } else if (_vaultSeed % 2 == 0) {
            usdc.mint(_amount, user);

            vm.startPrank(user);
            usdc.approve(address(usdcVault), _amount);
            usdcVault.deposit(_amount, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][wethVault] += _amount;
            usdcTotalDeposits += _amount;
        } else {
            link.mint(_amount, user);

            vm.startPrank(user);
            link.approve(address(linkVault), _amount);
            linkVault.deposit(_amount, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][wethVault] += _amount;
            linkTotalDeposits += _amount;
        }
    }

    function withdraw(uint256 _addressSeed, uint256 _amount, uint256 _vaultSeed) public {
        if (depositors.length() == 0) {
            deposit(_addressSeed, _amount, _vaultSeed);
        }
        address user = _indexToDepositorAddress(_addressSeed);

        if (depositorsToVaultsToAmounts[user][wethVault] > 0) {
            _amount = bound(_amount, 1, depositorsToVaultsToAmounts[user][wethVault]);

            vm.startPrank(user);
            wethVault.withdraw(_amount, user, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][wethVault] -= _amount;
            wethTotalDeposits -= _amount;
        } else if (depositorsToVaultsToAmounts[user][usdcVault] > 0) {
            _amount = bound(_amount, 1, depositorsToVaultsToAmounts[user][usdcVault]);

            vm.startPrank(user);
            usdcVault.withdraw(_amount, user, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][usdcVault] -= _amount;
            usdcTotalDeposits -= _amount;
        } else if (depositorsToVaultsToAmounts[user][linkVault] > 0) {
            _amount = bound(_amount, 1, depositorsToVaultsToAmounts[user][linkVault]);

            vm.startPrank(user);
            linkVault.withdraw(_amount, user, user);
            vm.stopPrank();

            depositorsToVaultsToAmounts[user][linkVault] -= _amount;
            linkTotalDeposits -= _amount;
        } else {
            revert("Insufficient balance across vaults for withdrawal");
        }
    }

    // // becomeGuardian
    // function createGuardianAndWethVault(uint256 _addressSeed) public returns (address guardian, address wethVault) {
    //     guardian = _seedToAddress(_addressSeed);

    //     weth.mint(mintAmount, guardian);

    //     vm.startPrank(guardian);
    //     weth.approve(address(vaultGuardians), mintAmount);
    //     wethVault = vaultGuardians.becomeGuardian(allocationData);
    //     vm.stopPrank();

    //     guardians.add(guardian);
    //     wethVaults.add(wethVault);
    //     guardiansToWethVaults[guardian] = wethVault;

    //     return (guardian, wethVault);
    // }

    // // becomeTokenGuardian
    // function createGuardianAndTokenVault(uint256 _addressSeed, uint256 _tokenSeed)
    //     public
    //     returns (address guardian, address tokenVault)
    // {
    //     if (guardians.length() == 0) {
    //         createGuardianAndWethVault(_addressSeed);
    //     }
    //     guardian = _indexToGuardianAddress(_addressSeed);

    //     vm.startPrank(guardian);

    //     if (_tokenSeed % 2 == 0) {
    //         usdc.mint(mintAmount, guardian);
    //         usdc.approve(address(vaultGuardians), mintAmount);
    //         tokenVault = vaultGuardians.becomeTokenGuardian(allocationData, IERC20(usdc));
    //         usdcVaults.add(tokenVault);
    //         guardiansToUsdcVaults[guardian] = tokenVault;
    //     } else {
    //         link.mint(mintAmount, guardian);
    //         link.approve(address(vaultGuardians), mintAmount);
    //         tokenVault = vaultGuardians.becomeTokenGuardian(allocationData, IERC20(link));
    //         linkVaults.add(tokenVault);
    //         guardiansToLinkVaults[guardian] = tokenVault;
    //     }

    //     vm.stopPrank();

    //     return (guardian, tokenVault);
    // }

    // // quitGuardian()
    // function quitGuardianWethVault(uint256 _addressSeed) public returns (uint256 amountOfAssetsReturned) {
    //     if (guardians.length() == 0) {
    //         createGuardianAndWethVault(_addressSeed);
    //     }
    //     address guardian = _indexToGuardianAddress(_addressSeed);
    //     address vault = guardiansToWethVaults[guardian];

    //     vm.startPrank(guardian);
    //     VaultShares(vault).approve(address(vaultGuardians), type(uint256).max);
    //     amountOfAssetsReturned = vaultGuardians.quitGuardian();
    //     vm.stopPrank();

    //     wethVaults.remove(vault);
    //     guardians.remove(guardian);
    //     delete guardiansToWethVaults[guardian];

    //     return amountOfAssetsReturned;
    // }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/

    function getWethVaultTotalAssets() public view returns (uint256) {
        return wethVault.totalAssets();
    }

    function getUsdcVaultTotalAssets() public view returns (uint256) {
        return usdcVault.totalAssets();
    }

    function getLinkVaultTotalAssets() public view returns (uint256) {
        return linkVault.totalAssets();
    }

    // utils
    /// @dev Convert a seed to an address
    function _seedToAddress(uint256 addressSeed) internal pure returns (address) {
        return address(uint160(bound(addressSeed, 1, type(uint160).max)));
    }

    /// @dev Convert an index to an existing guardian address
    function _indexToGuardianAddress(uint256 addressIndex) internal view returns (address) {
        return guardians.at(bound(addressIndex, 0, guardians.length() - 1));
    }

    /// @dev Convert an index to an existing depositor address
    function _indexToDepositorAddress(uint256 addressIndex) internal view returns (address) {
        return depositors.at(bound(addressIndex, 0, depositors.length() - 1));
    }
}
