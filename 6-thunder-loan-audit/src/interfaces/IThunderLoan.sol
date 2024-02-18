// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @audit-info the IThunderLoan contract should be implemented by the ThunderLoan contract
interface IThunderLoan {
    // @audit low/info ThunderLoan contract takes an IERC20, not address
    function repay(address token, uint256 amount) external;
}
