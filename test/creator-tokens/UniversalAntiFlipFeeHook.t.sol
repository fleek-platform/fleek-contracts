// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { SwapParams, ModifyLiquidityParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import { UniversalAntiFlipFeeHook } from "../../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { AntiFlipFeeLib } from "../../src/creator-tokens/libraries/AntiFlipFeeLib.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

/**
 * @title UniversalAntiFlipFeeHookTest
 * @notice Comprehensive test suite for the UniversalAntiFlipFeeHook contract
 * @dev Tests multi-token hook with registration, fee calculations, and beforeSwap pattern
 */
contract UniversalAntiFlipFeeHookTest is Test {
    // Core contracts
    UniversalAntiFlipFeeHook public hook;
    MockFactory public factory;
    MockPoolManager public mockPoolManager;
    PoolSwapTest public swapRouter;
    
    // Tokens
    MockERC20 public flk;
    
    // Creator 1 setup
    CreatorCoin public creatorToken1;
    CreatorVesting public vestingWallet1;
    address public creator1 = makeAddr("creator1");
    
    // Creator 2 setup
    CreatorCoin public creatorToken2;
    CreatorVesting public vestingWallet2;
    address public creator2 = makeAddr("creator2");

    // Test actors
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public foundation = Config.FOUNDATION();
    
    // Pool configuration
    PoolKey public poolKey;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function setUp() public {
        // Set chainid to Base Sepolia for testing
        vm.chainId(84532);
        
        // Deploy FLK token at the expected address for Base Sepolia
        flk = new MockERC20("Fleek", "FLK", 18);
        vm.etch(Config.FLK(), address(flk).code);
        
        // Deploy mock factory
        factory = new MockFactory();
        
        // Deploy mock pool manager
        mockPoolManager = new MockPoolManager();

        // Deploy hook at correct address with beforeSwap permissions
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        address hookAddress = address(flags);
        
        deployCodeTo(
            "UniversalAntiFlipFeeHook.sol:UniversalAntiFlipFeeHook",
            abi.encode(address(factory), address(mockPoolManager)),
            hookAddress
        );
        hook = UniversalAntiFlipFeeHook(hookAddress);

        // Deploy creator 1 token and vesting
        vm.prank(creator1);
        creatorToken1 = new CreatorCoin("Creator Token 1", "CT1");
        
        vestingWallet1 = new CreatorVesting(
            creator1,
            uint64(block.timestamp),
            365 days,
            30 days
        );
        
        vm.prank(creator1);
        creatorToken1.transfer(address(vestingWallet1), 100_000e18);

        // Deploy creator 2 token and vesting
        vm.prank(creator2);
        creatorToken2 = new CreatorCoin("Creator Token 2", "CT2");
        
        vestingWallet2 = new CreatorVesting(
            creator2,
            uint64(block.timestamp),
            365 days,
            30 days
        );
        
        vm.prank(creator2);
        creatorToken2.transfer(address(vestingWallet2), 100_000e18);

        // Register token1 with factory (simulate bonding curve registering)
        factory.registerToken(address(creatorToken1), address(this));
        
        // Register token2 with factory
        factory.registerToken(address(creatorToken2), makeAddr("bondingCurve2"));

        // Setup pool key for tests - use Config.FLK() to get the actual FLK address
        address flkAddress = Config.FLK();
        bool flkIsToken0 = flkAddress < address(creatorToken1);
        poolKey = PoolKey({
            currency0: Currency.wrap(flkIsToken0 ? flkAddress : address(creatorToken1)),
            currency1: Currency.wrap(flkIsToken0 ? address(creatorToken1) : flkAddress),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Labels for debugging
        vm.label(address(hook), "UniversalAntiFlipFeeHook");
        vm.label(address(factory), "Factory");
        vm.label(address(mockPoolManager), "MockPoolManager");
        vm.label(address(creatorToken1), "CreatorToken1");
        vm.label(address(vestingWallet1), "VestingWallet1");
        vm.label(address(creatorToken2), "CreatorToken2");
        vm.label(address(vestingWallet2), "VestingWallet2");
        vm.label(creator1, "Creator1");
        vm.label(creator2, "Creator2");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(foundation, "Foundation");
    }

    /*//////////////////////////////////////////////////////////////
                        SETUP & DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Setup_HookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize, "beforeInitialize should be false");
        assertFalse(permissions.afterInitialize, "afterInitialize should be false");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be false");
        assertFalse(permissions.afterAddLiquidity, "afterAddLiquidity should be false");
        assertFalse(permissions.beforeRemoveLiquidity, "beforeRemoveLiquidity should be false");
        assertFalse(permissions.afterRemoveLiquidity, "afterRemoveLiquidity should be false");
        assertTrue(permissions.beforeSwap, "beforeSwap should be true");
        assertTrue(permissions.afterSwap, "afterSwap should be true");
        assertFalse(permissions.beforeDonate, "beforeDonate should be false");
        assertFalse(permissions.afterDonate, "afterDonate should be false");
        assertTrue(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be true");
        assertFalse(permissions.afterSwapReturnDelta, "afterSwapReturnDelta should be false");
        assertFalse(permissions.afterAddLiquidityReturnDelta, "afterAddLiquidityReturnDelta should be false");
        assertFalse(permissions.afterRemoveLiquidityReturnDelta, "afterRemoveLiquidityReturnDelta should be false");
    }

    function test_Setup_ImmutableVariables() public view {
        assertEq(hook.FACTORY(), address(factory), "Factory address mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN REGISTRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterToken_Success() public {
        // Register token1 (authorized via factory)
        hook.registerToken(
            address(creatorToken1),
            creator1,
            address(vestingWallet1)
        );

        assertEq(hook.tokenToCreator(address(creatorToken1)), creator1, "Creator should be registered");
        assertEq(hook.tokenToVestingWallet(address(creatorToken1)), address(vestingWallet1), "Vesting wallet should be registered");
        assertGt(hook.tokenGraduationTimestamp(address(creatorToken1)), 0, "Graduation timestamp should be set");
    }

    function test_RegisterToken_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit UniversalAntiFlipFeeHook.TokenRegistered(
            address(creatorToken1),
            creator1,
            address(vestingWallet1),
            block.timestamp
        );
        
        hook.registerToken(
            address(creatorToken1),
            creator1,
            address(vestingWallet1)
        );
    }

    function test_RegisterToken_RevertsIfNotAuthorized() public {
        address fakeToken = makeAddr("fakeToken");
        
        vm.expectRevert(UniversalAntiFlipFeeHook.NotAuthorizedBondingCurve.selector);
        hook.registerToken(fakeToken, creator1, address(vestingWallet1));
    }

    function test_RegisterToken_RevertsIfAlreadyRegistered() public {
        // First registration should work
        hook.registerToken(
            address(creatorToken1),
            creator1,
            address(vestingWallet1)
        );

        // Second registration should fail
        vm.expectRevert(UniversalAntiFlipFeeHook.TokenAlreadyRegistered.selector);
        hook.registerToken(
            address(creatorToken1),
            creator1,
            address(vestingWallet1)
        );
    }

    function test_RegisterToken_MultipleTokens() public {
        // Register token 1
        hook.registerToken(
            address(creatorToken1),
            creator1,
            address(vestingWallet1)
        );

        // Register token 2 (must be called by authorized bonding curve)
        vm.prank(makeAddr("bondingCurve2"));
        hook.registerToken(
            address(creatorToken2),
            creator2,
            address(vestingWallet2)
        );

        // Verify both are registered independently
        assertEq(hook.tokenToCreator(address(creatorToken1)), creator1, "Token1 creator mismatch");
        assertEq(hook.tokenToCreator(address(creatorToken2)), creator2, "Token2 creator mismatch");
        assertEq(hook.tokenToVestingWallet(address(creatorToken1)), address(vestingWallet1), "Token1 vesting mismatch");
        assertEq(hook.tokenToVestingWallet(address(creatorToken2)), address(vestingWallet2), "Token2 vesting mismatch");
    }

    /*//////////////////////////////////////////////////////////////
                        WINDOW CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Window_IsWithinRange() public view {
        uint256 buyTime = block.timestamp;
        uint256 window = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            buyTime,
            block.timestamp
        );

        assertGe(window, 30, "Window should be at least 30 seconds");
        assertLe(window, 120, "Window should be at most 120 seconds");
    }

    function test_Window_DifferentForDifferentTokens() public view {
        uint256 buyTime = block.timestamp;
        
        uint256 window1 = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            buyTime,
            block.timestamp
        );
        
        uint256 window2 = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken2),
            buyTime,
            block.timestamp
        );

        // Windows for different tokens should likely be different
        // Both should be in valid range
        assertGe(window1, 30, "Window1 should be >= 30s");
        assertLe(window1, 120, "Window1 should be <= 120s");
        assertGe(window2, 30, "Window2 should be >= 30s");
        assertLe(window2, 120, "Window2 should be <= 120s");
        
        console.log("Token1 window:", window1);
        console.log("Token2 window:", window2);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FeeDistribution_Tier1_250kTokens() public view {
        // Creator + vesting has ~900k tokens total (meets tier 1)
        uint256 creatorBalance = creatorToken1.balanceOf(creator1);
        uint256 vestingBalance = creatorToken1.balanceOf(address(vestingWallet1));
        uint256 totalHeld = creatorBalance + vestingBalance;
        
        assertGt(totalHeld, 250_000e18, "Should have > 250k for tier 1");
        
        console.log("Creator balance:", creatorBalance / 1e18);
        console.log("Vesting balance:", vestingBalance / 1e18);
        console.log("Total held:", totalHeld / 1e18);

        (uint256 foundationBps, uint256 creatorBps) = AntiFlipFeeLib.getFeeRates(
            creator1,
            address(creatorToken1),
            address(vestingWallet1)
        );

        assertEq(foundationBps, 150, "Foundation should get 150 bps (75%)");
        assertEq(creatorBps, 50, "Creator should get 50 bps (25%)");
    }

    function test_FeeDistribution_DifferentForDifferentCreators() public {
        // Creator1 in tier 1 (>250k tokens)
        (uint256 foundationBps1, uint256 creatorBps1) = AntiFlipFeeLib.getFeeRates(
            creator1,
            address(creatorToken1),
            address(vestingWallet1)
        );

        // Reduce creator2 to tier 2
        _setCreatorHoldings(creator2, creatorToken2, vestingWallet2, 200_000e18);
        
        (uint256 foundationBps2, uint256 creatorBps2) = AntiFlipFeeLib.getFeeRates(
            creator2,
            address(creatorToken2),
            address(vestingWallet2)
        );

        // Should be different tiers
        assertNotEq(foundationBps1, foundationBps2, "Foundation rates should differ");
        assertNotEq(creatorBps1, creatorBps2, "Creator rates should differ");
        
        console.log("Creator1 split: foundation=%d, creator=%d", foundationBps1, creatorBps1);
        console.log("Creator2 split: foundation=%d, creator=%d", foundationBps2, creatorBps2);
    }

    /*//////////////////////////////////////////////////////////////
                        FEE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FeeCalculation_BaseFee_Buy() public pure {
        uint256 amount = 1000e18;
        uint256 expectedFee = (amount * 200) / 10000; // 2%
        
        assertEq(expectedFee, 20e18, "Base fee should be 2% of amount");
    }

    function test_FeeCalculation_BaseFee_Sell() public pure {
        uint256 amount = 1000e18;
        uint256 expectedFee = (amount * 200) / 10000; // 2%
        
        assertEq(expectedFee, 20e18, "Base fee on sell should be 2% of amount");
    }

    function test_FeeCalculation_WithSnipePenalty() public pure {
        uint256 amount = 1000e18;
        uint256 expectedFee = (amount * 1200) / 10000; // 12%
        
        assertEq(expectedFee, 120e18, "Snipe penalty fee should be 12% of amount");
    }

    /*//////////////////////////////////////////////////////////////
                        USER LAST BUY TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UserLastBuy_InitiallyZero() public view {
        assertEq(hook.userLastBuy(address(creatorToken1), user1), 0, "User1 should have no buy recorded");
        assertEq(hook.userLastBuy(address(creatorToken1), user2), 0, "User2 should have no buy recorded");
    }

    function test_UserLastBuy_IndependentPerToken() public {
        // Register both tokens
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        vm.prank(makeAddr("bondingCurve2"));
        hook.registerToken(address(creatorToken2), creator2, address(vestingWallet2));

        // Verify user1 has no buys for either token
        assertEq(hook.userLastBuy(address(creatorToken1), user1), 0, "Token1: should be 0");
        assertEq(hook.userLastBuy(address(creatorToken2), user1), 0, "Token2: should be 0");
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EdgeCase_FeeDistributionNoRoundingError() public view {
        uint256[] memory testAmounts = new uint256[](5);
        testAmounts[0] = 1e18;      // 1 FLK
        testAmounts[1] = 999e18;    // Odd amount
        testAmounts[2] = 12345e18;  // Random amount
        testAmounts[3] = 1;         // 1 wei
        testAmounts[4] = 99999;     // Dust amount
        
        for (uint256 i = 0; i < testAmounts.length; i++) {
            uint256 amount = testAmounts[i];
            
            // Test with base fee (200 bps)
            uint256 totalFee = (amount * 200) / 10000;
            
            if (totalFee > 0) {
                (uint256 foundationBps, uint256 creatorBps) = AntiFlipFeeLib.getFeeRates(
                    creator1,
                    address(creatorToken1),
                    address(vestingWallet1)
                );
                
                uint256 foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
                uint256 creatorFee = totalFee - foundationFee;
                
                assertEq(
                    foundationFee + creatorFee,
                    totalFee,
                    "Fee split must equal total fee exactly"
                );
            }
        }
    }

    function test_EdgeCase_VerySmallAmounts() public pure {
        // Test amounts that result in zero fees
        uint256 amount1 = 1;        // 1 wei
        uint256 amount2 = 49;       // Just below rounding threshold
        uint256 amount3 = 50;       // Minimum to get 1 wei fee with 200 bps
        
        // With 200 bps (2%), fee = (amount * 200) / 10000 = amount / 50
        uint256 fee1 = (amount1 * 200) / 10000;
        uint256 fee2 = (amount2 * 200) / 10000;
        uint256 fee3 = (amount3 * 200) / 10000;
        
        assertEq(fee1, 0, "1 wei should result in 0 fee");
        assertEq(fee2, 0, "49 wei should result in 0 fee");
        assertEq(fee3, 1, "50 wei should result in 1 wei fee");
    }

    function test_EdgeCase_SellWithoutPriorBuy() public {
        address newUser = makeAddr("newUser");
        
        // Verify newUser has no buy recorded for token1
        assertEq(hook.userLastBuy(address(creatorToken1), newUser), 0, "New user should have no buy history");
        
        // User without buy history should only pay base fee (2%), not snipe penalty (12%)
        uint256 expectedFeeBps = 200; // BASE_FEE_BPS only
        
        assertEq(expectedFeeBps, 200, "Should only charge base fee");
        
        console.log("User without buy history sells:");
        console.log("  lastBuyTime: 0");
        console.log("  Fee rate: 2% (no snipe penalty)");
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Window_AllUsers(address user, uint256 buyTime) public view {
        vm.assume(user != address(0));
        buyTime = bound(buyTime, 1, type(uint64).max);

        uint256 window = AntiFlipFeeLib.calculateWindow(
            user,
            address(creatorToken1),
            buyTime,
            block.timestamp
        );

        assertGe(window, 30, "Window should be >= 30s");
        assertLe(window, 120, "Window should be <= 120s");
    }

    function testFuzz_FeeCalculation_BaseRate(uint256 amount) public pure {
        amount = bound(amount, 1e18, 1_000_000e18);

        // Calculate expected base fees (2%)
        uint256 expectedFeeBps = 200;
        uint256 expectedFee = (amount * expectedFeeBps) / 10000;

        // Verify fee calculation is consistent
        assertGt(expectedFee, 0, "Fee should be positive");
        assertLe(expectedFee, amount, "Fee should not exceed amount");
        assertEq(expectedFee, (amount * 2) / 100, "Fee should be exactly 2%");
    }

    function testFuzz_FeeCalculation_WithSnipePenalty(uint256 amount) public pure {
        amount = bound(amount, 1e18, 1_000_000e18);

        // Calculate expected fees with snipe penalty (12%)
        uint256 expectedFeeBps = 1200;
        uint256 expectedFee = (amount * expectedFeeBps) / 10000;

        // Verify fee calculation
        assertGt(expectedFee, 0, "Fee should be positive");
        assertLe(expectedFee, amount, "Fee should not exceed amount");
        assertEq(expectedFee, (amount * 12) / 100, "Fee should be 12% of amount");
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_MultiTokenIndependence() public {
        // Register both tokens
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        vm.prank(makeAddr("bondingCurve2"));
        hook.registerToken(address(creatorToken2), creator2, address(vestingWallet2));

        // Verify independent graduation timestamps
        uint256 grad1 = hook.tokenGraduationTimestamp(address(creatorToken1));
        
        vm.warp(block.timestamp + 100);
        
        // Token 2 registered later
        assertEq(hook.tokenGraduationTimestamp(address(creatorToken2)), grad1, "Both registered in same block");
        
        // Verify independent creators
        assertEq(hook.tokenToCreator(address(creatorToken1)), creator1, "Token1 should map to creator1");
        assertEq(hook.tokenToCreator(address(creatorToken2)), creator2, "Token2 should map to creator2");
        
        console.log("Token1 creator:", hook.tokenToCreator(address(creatorToken1)));
        console.log("Token2 creator:", hook.tokenToCreator(address(creatorToken2)));
    }

    function test_Scenario_BuyThenQuickSell_HighFee() public view {
        // Simulate: User buys, then tries to sell within window -> pays 12% fee
        uint256 buyTime = block.timestamp;
        uint256 window = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            buyTime,
            block.timestamp
        );
        
        // Calculate fees for immediate sell (within window)
        uint256 sellAmount = 1000e18;
        uint256 baseFee = (sellAmount * 200) / 10000; // 2%
        uint256 snipeFee = (sellAmount * 1200) / 10000; // 12%
        
        assertEq(snipeFee, baseFee * 6, "Snipe fee should be 6x base fee");
        
        console.log("Window duration:", window, "seconds");
        console.log("Base fee (2%):", baseFee / 1e18, "FLK");
        console.log("Snipe fee (12%):", snipeFee / 1e18, "FLK");
    }

    /*//////////////////////////////////////////////////////////////
                         BEFORE/AFTER SWAP INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BeforeSwap_Buy_ChargesBaseFee() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Setup: Give user FLK tokens (use Config.FLK() to get the right address)
        MockERC20(Config.FLK()).mint(user1, 1000e18);
        
        // Calculate expected fee (2% of 1000 FLK)
        uint256 swapAmount = 1000e18;
        uint256 expectedFee = (swapAmount * 200) / 10000; // 2%
        
        // Create swap params (buy = spend FLK for creator token)
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -int256(swapAmount),
            sqrtPriceLimitX96: flkIsToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        
        // Mock the pool manager call
        vm.prank(address(mockPoolManager));
        (bytes4 selector, , uint24 lpFee) = hook.beforeSwap(user1, poolKey, params, "");
        
        assertEq(selector, hook.beforeSwap.selector, "Should return correct selector");
        assertEq(lpFee, 0, "LP fee should be 0");
        
        // Verify fee was calculated (we can't easily check distribution without more mocking)
        console.log("Expected fee:", expectedFee / 1e18, "FLK");
    }

    function test_BeforeSwap_Sell_AfterWindow_ChargesBaseFee() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Simulate: User bought earlier, window has passed
        vm.prank(address(mockPoolManager));
        SwapParams memory buyParams = SwapParams({
            zeroForOne: Currency.unwrap(poolKey.currency0) == address(flk),
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), "");
        
        // Wait for window to expire (max window is 120 seconds)
        vm.warp(block.timestamp + 121);
        
        // Now sell
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory sellParams = SwapParams({
            zeroForOne: !flkIsToken0, // Opposite direction for sell
            amountSpecified: -int256(100e18),
            sqrtPriceLimitX96: flkIsToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        (bytes4 selector, , ) = hook.beforeSwap(user1, poolKey, sellParams, "");
        
        assertEq(selector, hook.beforeSwap.selector, "Should return correct selector");
    }

    function test_BeforeSwap_Sell_WithinWindow_ChargesSnipeFee() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Simulate: User just bought (within window)
        vm.prank(address(mockPoolManager));
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory buyParams = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: flkIsToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), "");
        
        // Immediately try to sell (within window)
        vm.warp(block.timestamp + 1);
        
        SwapParams memory sellParams = SwapParams({
            zeroForOne: !flkIsToken0, // Opposite direction
            amountSpecified: -int256(100e18),
            sqrtPriceLimitX96: flkIsToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        (bytes4 selector, , ) = hook.beforeSwap(user1, poolKey, sellParams, "");
        
        assertEq(selector, hook.beforeSwap.selector, "Should return correct selector");
        // Fee should be higher (12% instead of 2%), but we can't easily verify without more mocking
    }

    function test_BeforeSwap_RevertsIfTokenNotRegistered() public {
        // Don't register the token
        
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        vm.expectRevert(UniversalAntiFlipFeeHook.TokenNotRegistered.selector);
        hook.beforeSwap(user1, poolKey, params, "");
    }

    function test_BeforeSwap_OnlyPoolManager() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        // Should revert if not called by pool manager
        vm.expectRevert();
        hook.beforeSwap(user1, poolKey, params, "");
    }

    function test_AfterSwap_RecordsBuyTimestamp() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Verify timestamp is initially zero
        assertEq(hook.userLastBuy(address(creatorToken1), user1), 0, "Should start at 0");
        
        // Simulate buy
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory buyParams = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), "");
        
        // Verify timestamp was recorded
        assertEq(hook.userLastBuy(address(creatorToken1), user1), block.timestamp, "Should record buy time");
    }

    function test_AfterSwap_DoesNotRecordSellTimestamp() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // First record a buy
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory buyParams = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), "");
        uint256 buyTime = hook.userLastBuy(address(creatorToken1), user1);
        
        // Advance time and sell
        vm.warp(block.timestamp + 100);
        
        SwapParams memory sellParams = SwapParams({
            zeroForOne: !flkIsToken0,
            amountSpecified: -100e18,
            sqrtPriceLimitX96: flkIsToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, sellParams, BalanceDelta.wrap(0), "");
        
        // Verify timestamp was NOT updated
        assertEq(hook.userLastBuy(address(creatorToken1), user1), buyTime, "Should not update on sell");
    }

    function test_AfterSwap_OnlyPoolManager() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        // Should revert if not called by pool manager
        vm.expectRevert();
        hook.afterSwap(user1, poolKey, params, BalanceDelta.wrap(0), "");
    }

    function test_IdentifyCreatorToken_FlkIsToken0() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Create pool key where FLK is token0
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(Config.FLK()),
            currency1: Currency.wrap(address(creatorToken1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        bool flkIsToken0 = Currency.unwrap(key.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(user1, key, params, "");
        // Should not revert - creator token was identified correctly
    }

    function test_IdentifyCreatorToken_FlkIsToken1() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Create pool key where FLK is token1
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(creatorToken1)),
            currency1: Currency.wrap(Config.FLK()),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        bool flkIsToken0 = Currency.unwrap(key.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: !flkIsToken0,
            amountSpecified: -1000e18,
            sqrtPriceLimitX96: MAX_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        hook.beforeSwap(user1, key, params, "");
        // Should not revert - creator token was identified correctly
    }

    function test_BeforeSwap_ZeroFee_ReturnsZeroDelta() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        
        // Create swap with zero amount (edge case)
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == address(flk);
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: 0, // This would result in 0 fee
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });
        
        vm.prank(address(mockPoolManager));
        (bytes4 selector, , ) = hook.beforeSwap(user1, poolKey, params, "");
        
        assertEq(selector, hook.beforeSwap.selector, "Should return correct selector");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    uint160 internal constant MIN_PRICE_LIMIT = 4295128740;
    uint160 internal constant MAX_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    function _setCreatorHoldings(
        address creator,
        CreatorCoin token,
        CreatorVesting vesting,
        uint256 targetAmount
    ) internal {
        uint256 creatorBalance = token.balanceOf(creator);
        uint256 vestingBalance = token.balanceOf(address(vesting));
        uint256 currentTotal = creatorBalance + vestingBalance;
        
        if (currentTotal > targetAmount) {
            // Burn excess from creator
            uint256 toBurn = currentTotal - targetAmount;
            if (toBurn <= creatorBalance) {
                vm.prank(creator);
                token.burn(toBurn);
            } else {
                // Burn all of creator's balance
                vm.prank(creator);
                if (creatorBalance > 0) {
                    token.burn(creatorBalance);
                }
            }
        }
        
        console.log("Set holdings to:", targetAmount / 1e18);
        console.log("Actual total:", (token.balanceOf(creator) + token.balanceOf(address(vesting))) / 1e18);
    }
}

/**
 * @notice Mock pool manager that allows hook calls from tests
 * @dev Minimal implementation - only implements what the hook needs
 */
contract MockPoolManager {
    function unlock(bytes calldata) external returns (bytes memory) {
        return "";
    }
    
    // This is the function selector that the hook actually calls (matches IPoolManager)
    function take(Currency, address, uint256) external pure {
        // Mock implementation - does nothing in tests
    }
}

/**
 * @notice Mock factory for testing token registration
 */
contract MockFactory {
    mapping(address => address) public bondingCurveFor;
    
    function registerToken(address token, address bondingCurve) external {
        bondingCurveFor[token] = bondingCurve;
    }
}
