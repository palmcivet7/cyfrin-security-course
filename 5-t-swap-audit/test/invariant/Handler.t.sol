// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    // ghost variables
    int256 startingY;
    int256 startingX;
    int256 public expectedDeltaY;
    int256 public expectedDeltaX;

    int256 public actualDeltaX;
    int256 public actualDeltaY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(pool.getWeth());
        poolToken = ERC20Mock(pool.getPoolToken());
    }

    // deposit, swapExactOutput

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 _outputWeth) public {
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        _outputWeth = bound(_outputWeth, minWeth, weth.balanceOf(address(pool)));
        if (_outputWeth >= weth.balanceOf(address(pool))) return;

        // ∆X
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            _outputWeth, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool))
        );
        if (poolTokenAmount > type(uint64).max) return;

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        expectedDeltaY = int256(-1) * int256(_outputWeth);
        expectedDeltaX = int256(poolTokenAmount);

        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, _outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

    function deposit(uint256 _wethAmount) public {
        // make sure its a "reasonable" amount
        // avoid weird overflow errors etc
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        _wethAmount = bound(_wethAmount, minWeth, type(uint64).max); // 18.446744073709551615

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        expectedDeltaY = int256(_wethAmount);
        expectedDeltaX = int256(pool.getPoolTokensToDepositBasedOnWeth(_wethAmount));

        // deposit
        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, _wethAmount);
        poolToken.mint(liquidityProvider, uint256(expectedDeltaX));
        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        pool.deposit(_wethAmount, 0, uint256(expectedDeltaX), uint64(block.timestamp));
        vm.stopPrank();

        // actual
        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }
}
