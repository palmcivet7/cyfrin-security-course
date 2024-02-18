// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IPoolFactory {
    // e this is probably the interface for working with the PoolFactory.sol from TSwap
    // qanswered why are we using tswap?
    // a we need it to get the value of a token to calculate the fees
    function getPool(address tokenAddress) external view returns (address);
}
