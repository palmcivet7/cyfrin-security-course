// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18);
        assertEq(weth.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;

        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        assert(weth.balanceOf(user) >= expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }

    ////// Proof of Code ///////

    function test_getInputAmountBasedOnOutput_takes_higher_fee() public {
        vm.startPrank(user);

        // Define input reserves, output reserves, and output amount
        uint256 inputReserves = 10000; // Example value
        uint256 outputReserves = 5000; // Example value
        uint256 outputAmount = 1000; // Example amount

        // Call the function with these values
        uint256 actualInputAmount = pool.getInputAmountBasedOnOutput(outputAmount, inputReserves, outputReserves);
        // Calculate the expected input amount with correct fee (0.3%)
        uint256 expectedInputAmount = ((inputReserves * outputAmount) * 1000) / ((outputReserves - outputAmount) * 997);

        // Assert that the actual input amount is higher than the expected amount
        assertGt(actualInputAmount, expectedInputAmount);
        console.log("Expected input amount:", expectedInputAmount);
        console.log("Actual input amount:", actualInputAmount);
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        // Simulate a user swapping to demonstrate the loss
        vm.startPrank(user);
        IERC20 inputToken = IERC20(address(poolToken)); // Assuming poolToken is the input token
        IERC20 outputToken = IERC20(address(weth)); // Assuming WETH is the output token
        uint64 deadline = uint64(block.timestamp + 1 hours); // Set a deadline for the swap

        // Record user's token balances before the swap
        uint256 userInitialInputTokenBalance = inputToken.balanceOf(user);
        uint256 userInitialOutputTokenBalance = outputToken.balanceOf(user);

        // Perform the swap
        poolToken.approve(address(pool), 100e18);
        pool.swapExactOutput(inputToken, outputToken, outputAmount, deadline);

        // Check user's token balances after the swap
        uint256 userFinalInputTokenBalance = inputToken.balanceOf(user);
        uint256 userFinalOutputTokenBalance = outputToken.balanceOf(user);

        // Calculate the amount of input tokens spent by the user
        uint256 inputTokensSpent = userInitialInputTokenBalance - userFinalInputTokenBalance;
        uint256 outputTokensReceived = userFinalOutputTokenBalance - userInitialOutputTokenBalance;

        // Assert that the user received the correct output amount
        assertEq(outputTokensReceived, outputAmount);
        // Assert that the user spent more input tokens than the expected amount
        assertGt(inputTokensSpent, expectedInputAmount);

        console.log("Output tokens received:", outputTokensReceived);
        console.log("Input tokens spent:", inputTokensSpent);
        vm.stopPrank();
    }

    function test_swapExactInput_returns_zero() public {
        uint256 zero = 0;

        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        IERC20 inputToken = IERC20(address(poolToken)); // Assuming poolToken is the input token
        uint256 inputAmount = 1000; // Example amount
        IERC20 outputToken = IERC20(address(weth)); // Assuming WETH is the output token
        uint256 minOutputAmount = 100; // Example amount
        uint64 deadline = uint64(block.timestamp + 1 hours); // Set a deadline for the swap

        vm.startPrank(user);
        poolToken.approve(address(pool), 100e18);

        uint256 returnedValue = pool.swapExactInput(inputToken, inputAmount, outputToken, minOutputAmount, deadline);

        vm.stopPrank();

        assertEq(zero, returnedValue);
    }

    function test_swapExactOutput_has_no_slippage_protection() public {
        poolToken.mint(user, 10000e18);
        vm.startPrank(liquidityProvider);
        weth.mint(address(pool), 50e18);
        poolToken.mint(address(pool), 5000e18);
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10000e18);

        uint256 outputAmount = 1e18; // User wants 1 WETH
        IERC20 inputToken = IERC20(address(poolToken));
        IERC20 outputToken = IERC20(address(weth));
        uint64 deadline = uint64(block.timestamp + 1 hours);

        // Record user's input token balance before the swap
        uint256 userInitialInputTokenBalance = inputToken.balanceOf(user);

        // Perform the swap
        pool.swapExactOutput(inputToken, outputToken, outputAmount, deadline);

        // Check user's input token balance after the swap
        uint256 userFinalInputTokenBalance = inputToken.balanceOf(user);

        // Calculate the amount of input tokens spent by the user
        uint256 inputTokensSpent = userInitialInputTokenBalance - userFinalInputTokenBalance;

        // Assert that the user spent significantly more input tokens due to lack of slippage protection
        // The expected amount should be significantly lower than the actual amount spent
        uint256 expectedInputAmount = 1000e18; // Example expected amount (needs to be realistic based on initial pool
            // reserves)
        assertGt(inputTokensSpent, expectedInputAmount);

        console.log("Expected input amount:", expectedInputAmount);
        console.log("Actual input amount:", inputTokensSpent);

        vm.stopPrank();
    }

    function test_sellPoolTokens_mismatches_input_and_output() public {
        // Mint additional tokens to the user and the pool
        poolToken.mint(user, 10000e18);
        uint256 poolTokenAmountToSell = 10e18; // Example amount of pool tokens to sell
        poolToken.mint(user, poolTokenAmountToSell);

        // Adjust pool reserves to create a more extreme condition
        vm.startPrank(liquidityProvider);
        weth.mint(address(pool), 100e18); // Example WETH reserve
        poolToken.mint(address(pool), 1000e18); // Example poolToken reserve, creating a high slippage scenario
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), type(uint256).max);

        // Record user's WETH balance before selling pool tokens
        uint256 userInitialWethBalance = weth.balanceOf(user);

        // User sells pool tokens
        pool.sellPoolTokens(poolTokenAmountToSell);

        // Record user's WETH balance after selling pool tokens
        uint256 userFinalWethBalance = weth.balanceOf(user);

        // Calculate the amount of WETH received
        uint256 wethReceived = userFinalWethBalance - userInitialWethBalance;

        // Calculate expected WETH if swapExactInput was used
        uint256 expectedWethWithExactInput = pool.getOutputAmountBasedOnInput(
            poolTokenAmountToSell, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool))
        );

        // Assert that the amount of WETH received is not what would be expected from swapExactInput
        assertNotEq(
            wethReceived,
            expectedWethWithExactInput,
            "User received an amount of WETH equivalent to swapExactInput, which is not expected."
        );

        console.log("Expected WETH with swapExactInput:", expectedWethWithExactInput);
        console.log("Actual WETH received:", wethReceived);

        vm.stopPrank();
    }

    function test_invariant_breaks() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        uint256 outputWeth = 1e17;

        vm.startPrank(user);
        poolToken.approve(address(pool), type(uint256).max);
        poolToken.mint(user, 100e18);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        int256 startingY = int256(weth.balanceOf(address(pool)));
        int256 expectedDeltaY = int256(-1) * int256(outputWeth);

        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        int256 actualDeltaY = int256(endingY) - int256(startingY);
        assertEq(actualDeltaY, expectedDeltaY);
    }
}
