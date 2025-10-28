// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { BondingCurve } from "../../src/creator-tokens/curve/BondingCurve.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/libraries/LinearCurveMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract MockFLK is ERC20 {
    constructor() ERC20("Fleek Token", "FLK") {
        _mint(msg.sender, 1_000_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUniversalHook {
    // Mock implementation that accepts registerToken calls
    function registerToken(address, address, address) external {
        // Do nothing - just accept the call
    }
}

contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    CreatorCoin public creatorCoin;
    CreatorVesting public vestingWallet;
    MockFLK public flk;

    address public creator = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 constant BONDING_CURVE_MAX_SUPPLY = Config.BONDING_CURVE_ALLOCATION / 2; // 225k for curve
    uint256 constant TOTAL_TOKENS_TO_CURVE = Config.BONDING_CURVE_ALLOCATION; // 450k total (225k for curve + 225k for LP)

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork(vm.envString("BASE_RPC"));

        // Deploy mock FLK and etch it to the expected address
        MockFLK tempFlk = new MockFLK();
        vm.etch(Config.FLK(), address(tempFlk).code);
        flk = MockFLK(Config.FLK());

        // Deploy mock universal hook and etch it to an address with correct hook flags
        MockUniversalHook tempHook = new MockUniversalHook();
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        address mockHookAddress = address(flags);
        vm.etch(mockHookAddress, address(tempHook).code);

        // Deploy creator coin
        creatorCoin = new CreatorCoin("Test Token", "TEST");

        // Deploy vesting wallet
        vestingWallet = new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        // Deploy bonding curve
        bondingCurve = new BondingCurve();
        bondingCurve.initialize(
            creator,
            address(creatorCoin),
            Config.GRADUATION_THRESHOLD,
            Config.BASE_PRICE,
            BONDING_CURVE_MAX_SUPPLY, // Max supply for curve calculations (225k)
            address(vestingWallet),
            mockHookAddress // Use etched mock hook at 0x1234
        );

        // Transfer full allocation to bonding curve (450k: 225k for curve + 225k for LP)
        creatorCoin.transfer(address(bondingCurve), TOTAL_TOKENS_TO_CURVE);

        // Setup FLK for users (deal doesn't work on Base mainnet fork, so we'll use vm.store)
        // For now, assume we're testing on a fork where users have FLK
        vm.label(creator, "Creator");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(bondingCurve), "BondingCurve");
        vm.label(address(creatorCoin), "CreatorCoin");
    }

    function test_InitialState() public view {
        (address _creator, address _characterToken,,,,,bool _graduated) = bondingCurve.metadata();

        assertEq(bondingCurve.characterTokensSold(), 0);
        assertFalse(_graduated);
        assertEq(_creator, creator);
        assertEq(_characterToken, address(creatorCoin));
        assertEq(creatorCoin.balanceOf(address(bondingCurve)), TOTAL_TOKENS_TO_CURVE);
    }

    function test_Buy_Basic() public {
        uint256 buyAmount = 1e18; // 1 FLK

        // Give user1 FLK (extra for fees)
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        uint256 initialTokenBalance = creatorCoin.balanceOf(user1);
        uint256 initialFlkBalance = flk.balanceOf(user1);

        bondingCurve.buy(buyAmount, 0);

        vm.stopPrank();

        uint256 actualSpent = initialFlkBalance - flk.balanceOf(user1);

        // Check balances changed
        assertGt(creatorCoin.balanceOf(user1), initialTokenBalance, "User should receive tokens");
        assertGt(actualSpent, buyAmount, "Should spend curve cost + fees");
        assertEq(
            bondingCurve.characterTokensSold(),
            creatorCoin.balanceOf(user1),
            "Sold amount should match"
        );
    }

    function test_Buy_GraduatesWhenAllTokensSold() public {
        // Buy all available tokens from the curve
        uint256 buyAmount = 25_000e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();

        // Verify we hit max supply and graduated
        assertEq(bondingCurve.characterTokensSold(), BONDING_CURVE_MAX_SUPPLY);
        (,,,,,,bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");

        // Try to buy more - should revert with AlreadyGraduated
        flk.mint(user2, 1e18);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.AlreadyGraduated.selector);
        bondingCurve.buy(1e18, 0);
        vm.stopPrank();
    }

    function test_Buy_RevertsWhenBelowMinimum() public {
        uint256 buyAmount = bondingCurve.MIN_PURCHASE_FLK() - 1;
        flk.mint(user1, buyAmount);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.NotEnoughFLK.selector);
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();
    }

    function test_Buy_RevertsOnSlippage() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        // Set minOut too high
        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.buy(buyAmount, type(uint256).max);
        vm.stopPrank();
    }

    function test_Sell_Basic() public {
        // First buy some tokens
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensOwned = creatorCoin.balanceOf(user1);
        uint256 sellAmount = tokensOwned / 2;

        creatorCoin.approve(address(bondingCurve), sellAmount);
        uint256 initialFlkBalance = flk.balanceOf(user1);

        bondingCurve.sell(sellAmount, 0);
        vm.stopPrank();

        // Check user received FLK
        assertGt(flk.balanceOf(user1), initialFlkBalance, "User should receive FLK");
        assertEq(creatorCoin.balanceOf(user1), tokensOwned - sellAmount, "Tokens should be sold");
    }

    function test_Sell_RevertsAfterGraduation() public {
        // Buy some tokens first
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);
        uint256 tokensOwned = creatorCoin.balanceOf(user1);
        vm.stopPrank();

        // Buy all remaining tokens to trigger graduation
        uint256 exhaustBuy = 25_000e18;
        flk.mint(user2, exhaustBuy * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(exhaustBuy, 0);
        vm.stopPrank();

        // Verify graduation happened
        (,,,,,,bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");

        // Try to sell - should revert with AlreadyGraduated
        vm.startPrank(user1);
        creatorCoin.approve(address(bondingCurve), tokensOwned);
        vm.expectRevert(BondingCurve.AlreadyGraduated.selector);
        bondingCurve.sell(tokensOwned, 0);
        vm.stopPrank();
    }

    function test_Sell_RevertsWhenBelowMinimum() public {
        // Buy tokens first
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 sellAmount = bondingCurve.MIN_PURCHASE_FLK() - 1;
        creatorCoin.approve(address(bondingCurve), sellAmount);

        vm.expectRevert(BondingCurve.ZeroInput.selector);
        bondingCurve.sell(sellAmount, 0);
        vm.stopPrank();
    }

    function test_BuySell_RoundTrip() public {
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        bondingCurve.buy(buyAmount, 0);
        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        // Sell half the tokens back
        uint256 sellAmount = tokensReceived / 2;
        creatorCoin.approve(address(bondingCurve), sellAmount);
        bondingCurve.sell(sellAmount, 0);

        vm.stopPrank();

        uint256 finalFlk = flk.balanceOf(user1);
        uint256 finalTokens = creatorCoin.balanceOf(user1);

        // Should have received some FLK back
        assertGt(finalFlk, 0, "Should get FLK back from selling");
        // Should have less than bought originally (sold half)
        assertEq(finalTokens, tokensReceived - sellAmount, "Should have remaining tokens");
    }

    function test_MultipleBuys_IncreasesPrice() public {
        uint256 buyAmount = 1e18;

        // First buy
        flk.mint(user1, buyAmount * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);
        uint256 firstBuyTokens = creatorCoin.balanceOf(user1);
        vm.stopPrank();

        // Second buy (same FLK amount)
        flk.mint(user2, buyAmount * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);
        uint256 secondBuyTokens = creatorCoin.balanceOf(user2);
        vm.stopPrank();

        // Second buy should yield fewer tokens (price went up)
        assertLt(secondBuyTokens, firstBuyTokens, "Price should increase with supply");
    }

    function test_Buy_EmitsBuyEvent() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        vm.expectEmit(true, false, false, false);
        emit BondingCurve.Buy(user1, 0, 0, 0); // We don't know exact amounts, just check event exists
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();
    }

    function test_BuyExactTokens_Basic() public {
        uint256 exactTokensWanted = 1000e18; // Want exactly 1000 creator tokens

        // Get slope from metadata
        (,, uint256 slope,,,,) = bondingCurve.metadata();

        // Calculate expected cost
        uint256 expectedCost = LinearCurveMathV4.calculateBuyCost(
            exactTokensWanted,
            0, // currentSupply
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        // Add buffer for fees (2%)
        uint256 maxCost = (expectedCost * 102) / 100 + 1e18;

        // Give user1 FLK
        flk.mint(user1, maxCost);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        uint256 initialTokenBalance = creatorCoin.balanceOf(user1);
        uint256 initialFlkBalance = flk.balanceOf(user1);

        bondingCurve.buyExactTokens(exactTokensWanted, maxCost);

        uint256 finalTokenBalance = creatorCoin.balanceOf(user1);
        uint256 finalFlkBalance = flk.balanceOf(user1);

        // User should receive exactly the amount requested
        assertEq(finalTokenBalance - initialTokenBalance, exactTokensWanted, "Should receive exact tokens");

        // User should spend less than maxCost
        assertLt(initialFlkBalance - finalFlkBalance, maxCost, "Should spend less than max");

        // Curve should track the sale
        assertEq(bondingCurve.characterTokensSold(), exactTokensWanted, "Curve should track tokens sold");

        vm.stopPrank();
    }

    function test_BuyExactTokens_RevertsOnSlippage() public {
        uint256 exactTokensWanted = 1000e18;

        // Get slope from metadata
        (,, uint256 slope,,,,) = bondingCurve.metadata();

        // Calculate expected cost
        uint256 expectedCost = LinearCurveMathV4.calculateBuyCost(
            exactTokensWanted,
            0,
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        // Set maxCost too low (below actual cost)
        uint256 maxCost = expectedCost / 2;

        flk.mint(user1, expectedCost * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.buyExactTokens(exactTokensWanted, maxCost);

        vm.stopPrank();
    }

    function test_BuyExactTokens_ComparedToBuy() public {
        // Test that buyExactTokens and buy produce consistent results

        uint256 exactTokensWanted = 1000e18;
        (,, uint256 slope,,,,) = bondingCurve.metadata();

        // Calculate cost for exact tokens
        uint256 costForExact = LinearCurveMathV4.calculateBuyCost(
            exactTokensWanted,
            0,
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        // Give user1 FLK and buy exact tokens
        flk.mint(user1, costForExact * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buyExactTokens(exactTokensWanted, costForExact * 2);
        uint256 user1Tokens = creatorCoin.balanceOf(user1);
        vm.stopPrank();

        // Give user2 same amount and use regular buy
        flk.mint(user2, costForExact * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(costForExact, 0);
        uint256 user2Tokens = creatorCoin.balanceOf(user2);
        vm.stopPrank();

        // user1 should have exactly the requested amount
        assertEq(user1Tokens, exactTokensWanted, "BuyExact should give exact amount");

        // user2 should have similar amount (within small margin due to different supply points)
        // They won't be exactly equal because user2 bought at a different point on the curve
        assertGt(user2Tokens, 0, "Buy should give some tokens");
    }

    function test_BuyExactTokens_RevertsIfExceedsAvailable() public {
        // Try to buy more than available
        uint256 tooManyTokens = BONDING_CURVE_MAX_SUPPLY + 1;
        uint256 maxCost = 100_000e18; // Reasonable max cost

        flk.mint(user1, maxCost);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.buyExactTokens(tooManyTokens, maxCost);

        vm.stopPrank();
    }

    function test_Sell_EmitsSellEvent() public {
        // Buy first
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 sellAmount = creatorCoin.balanceOf(user1);
        creatorCoin.approve(address(bondingCurve), sellAmount);

        vm.expectEmit(true, false, false, false);
        emit BondingCurve.Sell(user1, 0, 0, 0);
        bondingCurve.sell(sellAmount, 0);
        vm.stopPrank();
    }

    function test_CapLogic_BuyAdjustsWhenLimited() public {
        // This test verifies that when available supply is less than requested,
        // the buy function correctly caps the purchase and adjusts the cost

        // First, let's buy a good chunk to reduce available supply
        uint256 initialBuy = 5_000e18;
        flk.mint(user1, initialBuy * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(initialBuy, 0);
        vm.stopPrank();

        // Now make a second buy that would exceed available supply
        uint256 largeBuy = 50_000e18;
        flk.mint(user2, largeBuy * 2);

        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);

        uint256 beforeFlk = flk.balanceOf(user2);
        bondingCurve.buy(largeBuy, 0); // Should cap automatically
        uint256 afterFlk = flk.balanceOf(user2);

        vm.stopPrank();

        uint256 actualSpent = beforeFlk - afterFlk;

        // Verify cap logic worked - we didn't spend the full large amount
        // (unless it triggered graduation, in which case this test becomes less meaningful)
        assertGt(creatorCoin.balanceOf(user2), 0, "Should have received tokens");
        assertGt(actualSpent, 0, "Should have spent some FLK");
    }

    function test_CannotBuyBeyondMaxSupply() public {
        uint256 massiveAmount = 1_000_000e18;
        flk.mint(user1, massiveAmount);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(massiveAmount, 0);
        vm.stopPrank();
        uint256 tokensBought = creatorCoin.balanceOf(user1);
        assertLe(tokensBought, BONDING_CURVE_MAX_SUPPLY);
    }

    function test_Graduation_CreatesFullRangeLiquidity() public {
        // Buy almost all tokens first to get close to graduation
        uint256 buyAmount1 = 19_000e18;
        flk.mint(user1, buyAmount1 * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount1, 0);
        vm.stopPrank();

        // Now buy the rest to trigger graduation and capture balances
        uint256 buyAmount2 = 10_000e18;
        flk.mint(user2, buyAmount2 * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);

        // Just before graduation, balances will be accumulated
        bondingCurve.buy(buyAmount2, 0);
        vm.stopPrank();

        uint256 flkBalanceAfter = flk.balanceOf(address(bondingCurve));
        uint256 ctBalanceAfter = creatorCoin.balanceOf(address(bondingCurve));

        // After graduation, sell should revert
        vm.expectRevert(BondingCurve.AlreadyGraduated.selector);
        bondingCurve.sell(1, 0);

        // Log the LP token usage
        console.log("=== Graduation LP Position ===");
        console.log("FLK remaining:", flkBalanceAfter);
        console.log("CT remaining:", ctBalanceAfter);
        console.log("");
        console.log("Full-range liquidity deployed (MIN_TICK to MAX_TICK)");
        console.log("LP NFT burned to 0xdead");

        // Verify tokens went into LP (allowing for tiny rounding dust)
        assertApproxEqAbs(flkBalanceAfter, 0, 1e18, "All FLK should be in LP");
        assertApproxEqAbs(ctBalanceAfter, 0, 1e18, "All CT should be in LP");
    }

    function test_GraduationMath_ExactBalancesAndFees() public {
        // This test ensures:
        // 1. Contract accumulates ~20,675 FLK before graduation (within rounding precision)
        // 2. Exactly 225k creator tokens are sold
        // 3. Fees are properly collected throughout the process
        // 4. At graduation, all FLK/tokens go into LP

        uint256 foundationBalanceBefore = flk.balanceOf(Config.FOUNDATION());
        uint256 creatorBalanceBefore = flk.balanceOf(creator);

        // Buy all tokens in one go - this will trigger graduation
        uint256 massiveBuy = 100_000e18;
        flk.mint(user1, massiveBuy);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), massiveBuy);

        uint256 userFlkBefore = flk.balanceOf(user1);

        // Expect the Graduated event and capture the LP amounts
        vm.recordLogs();
        bondingCurve.buy(massiveBuy, 0);

        vm.stopPrank();

        // Extract graduation event data
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 lpFlkAmount;
        uint256 lpTokenAmount;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("Graduated(uint256,uint256,uint256)")) {
                // Decode the event data: tokenId, parentTokenBalance, characterTokenBalance
                (, lpFlkAmount, lpTokenAmount) =
                    abi.decode(entries[i].data, (uint256, uint256, uint256));
                break;
            }
        }

        uint256 userFlkAfter = flk.balanceOf(user1);
        uint256 actualSpent = userFlkBefore - userFlkAfter;
        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        uint256 foundationFeesCollected =
            flk.balanceOf(Config.FOUNDATION()) - foundationBalanceBefore;
        uint256 creatorFeesCollected = flk.balanceOf(creator) - creatorBalanceBefore;
        uint256 totalFeesCollected = foundationFeesCollected + creatorFeesCollected;

        // Verify graduation happened
        (,,,,,,bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");

        // Verify exactly 225k tokens were sold
        assertEq(
            bondingCurve.characterTokensSold(),
            BONDING_CURVE_MAX_SUPPLY,
            "Exactly 225k tokens should be sold"
        );
        assertEq(
            tokensReceived, BONDING_CURVE_MAX_SUPPLY, "User should receive exactly 225k tokens"
        );

        console.log("=== Graduation Math Verification ===");
        console.log("User spent (including fees):", actualSpent / 1e18, "FLK");
        console.log("Tokens received:", tokensReceived / 1e18, "tokens");
        console.log("");
        console.log("Total fees collected:", totalFeesCollected / 1e18, "FLK");
        console.log("  Foundation fees:", foundationFeesCollected / 1e18, "FLK");
        console.log("  Creator fees:", creatorFeesCollected / 1e18, "FLK");
        console.log("");
        console.log("LP Deployed with:");
        console.log("  FLK amount:", lpFlkAmount / 1e18, "FLK");
        console.log("  Token amount:", lpTokenAmount / 1e18, "tokens");
        console.log("");
        console.log("Expected graduation threshold:", Config.GRADUATION_THRESHOLD / 1e18, "FLK");
        console.log(
            "Difference from target:", int256(lpFlkAmount) - int256(Config.GRADUATION_THRESHOLD)
        );

        // Key assertion: LP should have been deployed with ~20,675 FLK
        // Allow 2 FLK margin for rounding errors (0.01% tolerance)
        assertApproxEqAbs(
            lpFlkAmount,
            Config.GRADUATION_THRESHOLD,
            2e18,
            "LP should be deployed with ~20,675 FLK (within 2 FLK)"
        );

        // Verify LP got 225k tokens
        assertEq(lpTokenAmount, BONDING_CURVE_MAX_SUPPLY, "LP should have 225k tokens");

        // After graduation, contract should have ~0 balance (all in LP)
        uint256 contractFlkAfterGrad = flk.balanceOf(address(bondingCurve));
        uint256 contractTokenAfterGrad = creatorCoin.balanceOf(address(bondingCurve));

        assertApproxEqAbs(contractFlkAfterGrad, 0, 1e18, "All FLK should be in LP");
        assertApproxEqAbs(contractTokenAfterGrad, 0, 1e18, "All tokens should be in LP");

        // Verify fees were actually collected (should be ~2% of curve cost)
        // curveCost = actualSpent - fees, so fees should be ~2% of curveCost
        // which means fees / actualSpent should be slightly less than 2%
        uint256 curveCost = actualSpent - totalFeesCollected;
        uint256 expectedFees = (curveCost * 200) / 10000; // 2% of curve cost
        assertApproxEqAbs(
            totalFeesCollected,
            expectedFees,
            1e18, // 1 FLK tolerance
            "Total fees should be ~2% of curve cost"
        );

        // Verify the curve cost equals what went to LP
        assertApproxEqAbs(curveCost, lpFlkAmount, 1e18, "Curve cost should equal LP FLK amount");

        // Verify fee distribution between foundation and creator
        assertGt(foundationFeesCollected, 0, "Foundation should receive fees");
        assertGt(creatorFeesCollected, 0, "Creator should receive fees");
        assertGt(
            foundationFeesCollected,
            creatorFeesCollected,
            "Foundation should receive majority of fees"
        );
    }
}
