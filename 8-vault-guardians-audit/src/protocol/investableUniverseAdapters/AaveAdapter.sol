// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPool} from "../../vendor/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// xq is this contract how we interact with Aave? is it the ONLY way to interact with Aave?
// should it be the only way to interact with Aave?
// a yes this is how we interact with Aave.
contract AaveAdapter {
    using SafeERC20 for IERC20;

    error AaveAdapter__TransferFailed();

    IPool public immutable i_aavePool;

    constructor(address aavePool) {
        i_aavePool = IPool(aavePool);
    }

    // xq is the asset any ERC20 or just the one specific to the Vault?
    // a just the one specific to the vault
    // @skipped-followup is there an mev vulnerability here?
    function _aaveInvest(IERC20 asset, uint256 amount) internal {
        bool succ = asset.approve(address(i_aavePool), amount);
        if (!succ) {
            revert AaveAdapter__TransferFailed();
        }
        i_aavePool.supply({asset: address(asset), amount: amount, onBehalfOf: address(this), referralCode: 0});
    }

    // @written-info `amountOfAssetReturned` is unused named parameter
    function _aaveDivest(IERC20 token, uint256 amount) internal returns (uint256 amountOfAssetReturned) {
        i_aavePool.withdraw({asset: address(token), amount: amount, to: address(this)});
    }
}
