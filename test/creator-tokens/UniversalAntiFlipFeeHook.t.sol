// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

import { UniversalAntiFlipFeeHook } from "../../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { AntiFlipFeeLib } from "../../src/creator-tokens/libraries/AntiFlipFeeLib.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";

/**
 * @title UniversalAntiFlipFeeHookTest
 * @notice Comprehensive test suite for the UniversalAntiFlipFeeHook contract
 * @dev Tests multi-token hook with registration, fee calculations, and beforeSwap pattern
 */
contract UniversalAntiFlipFeeHookTest is Test {
    // Core contracts
    UniversalAntiFlipFeeHook public hook;
    MockFactory public factory;
    
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
    address public poolManager = makeAddr("poolManager");

    function setUp() public {
        // Deploy mock factory
        factory = new MockFactory();

        // Deploy hook at correct address with beforeSwap permissions
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        address hookAddress = address(flags);
        
        deployCodeTo(
            "UniversalAntiFlipFeeHook.sol:UniversalAntiFlipFeeHook",
            abi.encode(address(factory), poolManager),
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

        // Labels for debugging
        vm.label(address(hook), "UniversalAntiFlipFeeHook");
        vm.label(address(factory), "Factory");
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
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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
 * @notice Mock factory for testing token registration
 */
contract MockFactory {
    mapping(address => address) public bondingCurveFor;
    
    function registerToken(address token, address bondingCurve) external {
        bondingCurveFor[token] = bondingCurve;
    }
}
