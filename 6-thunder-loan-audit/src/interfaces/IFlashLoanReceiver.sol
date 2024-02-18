// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

// @audit-info unused import(?)
// this import is only used for a mock
// it is bad practice to edit live code for tests/mocks - replace import from `MockFlashLoanReceive.sol`
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    // qanswered is `token` the token that is being borrowed?
    // a yes
    // @audit-info where natspec?
    // qanswered `amount` is amount of tokens?
    // a yes
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
