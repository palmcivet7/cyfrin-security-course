// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC4626, ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IVaultShares, IERC4626} from "../interfaces/IVaultShares.sol";
import {AaveAdapter, IPool} from "./investableUniverseAdapters/AaveAdapter.sol";
import {UniswapAdapter} from "./investableUniverseAdapters/UniswapAdapter.sol";
import {DataTypes} from "../vendor/DataTypes.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// @done-followup ERC4626 inflation attacks
contract VaultShares is ERC4626, IVaultShares, AaveAdapter, UniswapAdapter, ReentrancyGuard {
    error VaultShares__DepositMoreThanMax(uint256 amount, uint256 max);
    // @written-info this error isnt being used anywhere because the modifier isnt being used anywhere
    error VaultShares__NotGuardian();
    error VaultShares__NotVaultGuardianContract();
    error VaultShares__AllocationNot100Percent(uint256 totalAllocation);
    error VaultShares__NotActive();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 internal immutable i_uniswapLiquidityToken;
    IERC20 internal immutable i_aaveAToken;
    address private immutable i_guardian;
    address private immutable i_vaultGuardians;
    uint256 private immutable i_guardianAndDaoCut;
    bool private s_isActive;

    AllocationData private s_allocationData; // e struct containing uint256 hold, uni, aave allocations

    // xq why is this 1000?
    // a easy divisor
    uint256 private constant ALLOCATION_PRECISION = 1_000;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event UpdatedAllocation(AllocationData allocationData);
    event NoLongerActive();
    event FundsInvested();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    // @written-info this modifier isnt being used anywhere
    modifier onlyGuardian() {
        if (msg.sender != i_guardian) {
            revert VaultShares__NotGuardian();
        }
        _;
    }

    modifier onlyVaultGuardians() {
        if (msg.sender != i_vaultGuardians) {
            revert VaultShares__NotVaultGuardianContract();
        }
        _;
    }

    modifier isActive() {
        if (!s_isActive) {
            revert VaultShares__NotActive();
        }
        _;
    }

    // slither-disable-start reentrancy-eth
    modifier divestThenInvest() {
        uint256 uniswapLiquidityTokensBalance = i_uniswapLiquidityToken.balanceOf(address(this));
        uint256 aaveAtokensBalance = i_aaveAToken.balanceOf(address(this));

        // Divest
        if (uniswapLiquidityTokensBalance > 0) {
            _uniswapDivest(IERC20(asset()), uniswapLiquidityTokensBalance);
        }
        if (aaveAtokensBalance > 0) {
            _aaveDivest(IERC20(asset()), aaveAtokensBalance);
        }

        // xq we want the other code ran here? before the _investFunds??
        // a yes, funds are withdrawn here
        _;

        // Reinvest
        if (s_isActive) {
            _investFunds(IERC20(asset()).balanceOf(address(this)));
        }
    }
    // slither-disable-end reentrancy-eth

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // We use a struct to avoid stack too deep errors. Thanks Solidity
    // xq this is interesting and unusual. is there anything that could go wrong with using a struct?
    // a dont think so
    // xq where is this struct coming from?
    // a ConstructorData struct is in IVaultShares interface
    constructor(ConstructorData memory constructorData)
        ERC4626(constructorData.asset)
        ERC20(constructorData.vaultName, constructorData.vaultSymbol)
        AaveAdapter(constructorData.aavePool)
        UniswapAdapter(constructorData.uniswapRouter, constructorData.weth, constructorData.usdc)
    {
        i_guardian = constructorData.guardian;
        i_guardianAndDaoCut = constructorData.guardianAndDaoCut;
        i_vaultGuardians = constructorData.vaultGuardians;
        s_isActive = true;
        updateHoldingAllocation(constructorData.allocationData);

        // External calls
        i_aaveAToken =
            IERC20(IPool(constructorData.aavePool).getReserveData(address(constructorData.asset)).aTokenAddress);
        i_uniswapLiquidityToken = IERC20(i_uniswapFactory.getPair(address(constructorData.asset), address(i_weth)));
    }

    // xq is there no way to reactivate? what happens if a vault is no longer active?
    // nope, this is when a guardian quits
    // @skipped-followup would it be cheaper in terms of gas to have a paused/inactive bool set to true?
    // xq should the i_guardian be the one to decide this? and not the vault guardians contract???
    // a this is called by the guardian via the guardians base with _quitGuardian()
    function setNotActive() public onlyVaultGuardians isActive {
        s_isActive = false;
        emit NoLongerActive();
    }

    // xq what if a shares holder transferred their shares to address(0)??
    // a they cant (0 checks)
    // xq would the protocol not be able to transfer tokens back to them? causing a denial of service?
    // see above

    // e the vault guardian updates how much the vault allocates to holding, uni, and aave
    // xq should the i_guardian be the one to decide this? and not the vault guardians contract???
    // a this is called by the guardian via the guardians base with updateHoldingAllocation()
    function updateHoldingAllocation(AllocationData memory tokenAllocationData) public onlyVaultGuardians isActive {
        uint256 totalAllocation = tokenAllocationData.holdAllocation + tokenAllocationData.uniswapAllocation
            + tokenAllocationData.aaveAllocation;
        // xq totalAllocation has to equal 1000??
        // a seems so
        // xq what happens if aave or uniswap blocked the vault shares addresses?
        // a protocol will possibly be affected but its outside the scope of this review
        if (totalAllocation != ALLOCATION_PRECISION) {
            revert VaultShares__AllocationNot100Percent(totalAllocation);
        }
        s_allocationData = tokenAllocationData;
        emit UpdatedAllocation(tokenAllocationData);
    }

    /**
     * @dev See {IERC4626-deposit}. Overrides the Openzeppelin implementation.
     *
     * @notice Mints shares to the DAO and the guardian as a fee
     */
    // slither-disable-start reentrancy-eth
    // @written-info could this be marked external?
    // xq could passing a weird address as receiver cause DoS?
    // a no, doesnt seem to
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626, IERC4626)
        isActive
        nonReentrant
        returns (uint256)
    {
        if (assets > maxDeposit(receiver)) {
            revert VaultShares__DepositMoreThanMax(assets, maxDeposit(receiver));
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        _mint(i_guardian, shares / i_guardianAndDaoCut);
        _mint(i_vaultGuardians, shares / i_guardianAndDaoCut);

        _investFunds(assets);
        return shares;
    }

    function _investFunds(uint256 assets) private {
        uint256 uniswapAllocation = (assets * s_allocationData.uniswapAllocation) / ALLOCATION_PRECISION;
        uint256 aaveAllocation = (assets * s_allocationData.aaveAllocation) / ALLOCATION_PRECISION;

        emit FundsInvested();

        _uniswapInvest(IERC20(asset()), uniswapAllocation);
        _aaveInvest(IERC20(asset()), aaveAllocation);
    }

    // slither-disable-start reentrancy-benign
    /* 
     * @notice Unintelligently just withdraws everything, and then reinvests it all. 
     * @notice Anyone can call this and pay the gas costs to rebalance the portfolio at any time. 
     * @dev We understand that this is horrible for gas costs. 
     */
    // @skipped-followup anyone can call this? is that a bad thing?
    function rebalanceFunds() public isActive divestThenInvest nonReentrant {}

    /**
     * @dev See {IERC4626-withdraw}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
    // @written-info could this be marked external?
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    {
        uint256 shares = super.withdraw(assets, receiver, owner);
        return shares;
    }

    /**
     * @dev See {IERC4626-redeem}.
     *
     * We first divest our assets so we get a good idea of how many assets we hold.
     * Then, we redeem for the user, and automatically reinvest.
     */
    // @written-info could this be marked external?
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(IERC4626, ERC4626)
        divestThenInvest
        nonReentrant
        returns (uint256)
    {
        uint256 assets = super.redeem(shares, receiver, owner);
        return assets;
    }
    // slither-disable-end reentrancy-eth
    // slither-disable-end reentrancy-benign

    /*//////////////////////////////////////////////////////////////
                             VIEW AND PURE
    //////////////////////////////////////////////////////////////*/
    function getGuardian() external view returns (address) {
        return i_guardian;
    }

    function getGuardianAndDaoCut() external view returns (uint256) {
        return i_guardianAndDaoCut;
    }

    function getVaultGuardians() external view returns (address) {
        return i_vaultGuardians;
    }

    function getIsActive() external view returns (bool) {
        return s_isActive;
    }

    function getAaveAToken() external view returns (address) {
        return address(i_aaveAToken);
    }

    function getUniswapLiquidtyToken() external view returns (address) {
        return address(i_uniswapLiquidityToken);
    }

    function getAllocationData() external view returns (AllocationData memory) {
        return s_allocationData;
    }
}
