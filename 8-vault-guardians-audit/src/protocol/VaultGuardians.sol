/**
 *  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 * |_|                                                                                          |_|
 * |_| █████   █████                      ████   █████                                          |_|
 * |_|░░███   ░░███                      ░░███  ░░███                                           |_|
 * |_| ░███    ░███   ██████   █████ ████ ░███  ███████                                         |_|
 * |_| ░███    ░███  ░░░░░███ ░░███ ░███  ░███ ░░░███░                                          |_|
 * |_| ░░███   ███    ███████  ░███ ░███  ░███   ░███                                           |_|
 * |_|  ░░░█████░    ███░░███  ░███ ░███  ░███   ░███ ███                                       |_|
 * |_|    ░░███     ░░████████ ░░████████ █████  ░░█████                                        |_|
 * |_|     ░░░       ░░░░░░░░   ░░░░░░░░ ░░░░░    ░░░░░                                         |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|                                                                                          |_|
 * |_|   █████████                                     █████  ███                               |_|
 * |_|  ███░░░░░███                                   ░░███  ░░░                                |_|
 * |_| ███     ░░░  █████ ████  ██████   ████████   ███████  ████   ██████   ████████    █████  |_|
 * |_|░███         ░░███ ░███  ░░░░░███ ░░███░░███ ███░░███ ░░███  ░░░░░███ ░░███░░███  ███░░   |_|
 * |_|░███    █████ ░███ ░███   ███████  ░███ ░░░ ░███ ░███  ░███   ███████  ░███ ░███ ░░█████  |_|
 * |_|░░███  ░░███  ░███ ░███  ███░░███  ░███     ░███ ░███  ░███  ███░░███  ░███ ░███  ░░░░███ |_|
 * |_| ░░█████████  ░░████████░░████████ █████    ░░████████ █████░░████████ ████ █████ ██████  |_|
 * |_|  ░░░░░░░░░    ░░░░░░░░  ░░░░░░░░ ░░░░░      ░░░░░░░░ ░░░░░  ░░░░░░░░ ░░░░ ░░░░░ ░░░░░░   |_|
 * |_| _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _  _ |_|
 * |_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_||_|
 */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {VaultGuardiansBase, IERC20, SafeERC20} from "./VaultGuardiansBase.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/* 
 * @title VaultGuardians
 * @author Vault Guardian
 * @notice This contract is the entry point for the Vault Guardian system.
 * @notice It includes all the functionality that the DAO has control over. 
 * @notice the VaultGuardiansBase has all the users & guardians functionality.
 */
contract VaultGuardians is Ownable, VaultGuardiansBase {
    using SafeERC20 for IERC20;

    error VaultGuardians__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event VaultGuardians__UpdatedStakePrice(uint256 oldStakePrice, uint256 newStakePrice);
    // @written-info this event isnt being used in this contract
    event VaultGuardians__UpdatedFee(uint256 oldFee, uint256 newFee);
    event VaultGuardians__SweptTokens(address asset);

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(
        address aavePool,
        address uniswapV2Router,
        address weth,
        address tokenOne,
        address tokenTwo,
        address vaultGuardiansToken
    )
        Ownable(msg.sender)
        VaultGuardiansBase(aavePool, uniswapV2Router, weth, tokenOne, tokenTwo, vaultGuardiansToken)
    {}

    /*
     * @notice Updates the stake price for guardians. 
     * @param newStakePrice The new stake price in wei
     */
    // xq what is this price for?
    // a i_guardianAndDaoCut in VaultShares: when deposits are made the guardian and the vault get shares / i_guardianAndDaoCut
    function updateGuardianStakePrice(uint256 newStakePrice) external onlyOwner {
        s_guardianStakePrice = newStakePrice;
        // @written-followup are these values being emitted the same?
        emit VaultGuardians__UpdatedStakePrice(s_guardianStakePrice, newStakePrice);
    }

    /*
     * @notice Updates the percentage shares guardians & Daos get in new vaults
     * @param newCut the new cut
     * @dev this value will be divided by the number of shares whenever a user deposits into a vault
     * @dev historical vaults will not have their cuts updated, only vaults moving forward
     */
    // @written-follow up "this value will be divided by the number of shares"
    // in VaultShares, it is: `shares / i_guardianAndDaoCut`
    function updateGuardianAndDaoCut(uint256 newCut) external onlyOwner {
        s_guardianAndDaoCut = newCut;
        // @written-followup are these values being emitted the same?
        // @written-low shouldn't this event be `VaultGuardians__UpdatedFee` ?
        emit VaultGuardians__UpdatedStakePrice(s_guardianAndDaoCut, newCut);
    }

    /*
     * @notice Any excess ERC20s can be scooped up by the DAO. 
     * @notice This is often just little bits left around from swapping or rounding errors
     * @dev Since this is owned by the DAO, the funds will always go to the DAO. 
     * @param asset The ERC20 to sweep
     */
    // e anyone can call this function to send any ERC20s held by this contract to the DAO
    // @written-info lack of access control
    function sweepErc20s(IERC20 asset) external {
        uint256 amount = asset.balanceOf(address(this));
        emit VaultGuardians__SweptTokens(address(asset));
        // xq the owner is the dao?
        // a yes, VaultGuardianGovernor is the owner of address(this)
        asset.safeTransfer(owner(), amount);
    }
}
