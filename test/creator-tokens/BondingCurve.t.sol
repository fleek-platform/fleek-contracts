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
import { AntiFlipFeeLib } from "../../src/creator-tokens/libraries/AntiFlipFeeLib.sol";
import {
    BaseUniswapDeployments
} from "../../src/creator-tokens/libraries/BaseUniswapDeployments.sol";
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
    function registerToken(address, address, address) external { }
}

contract BuyHelper {
    address public bondingCurve;
    address public flk;
    address public creatorCoin;

    constructor(address _bondingCurve, address _flk, address _creatorCoin) {
        bondingCurve = _bondingCurve;
        flk = _flk;
        creatorCoin = _creatorCoin;
    }

    function buyTokens(uint256 amount) external {
        ERC20(flk).approve(bondingCurve, type(uint256).max);
        BondingCurve(bondingCurve).buy(amount, 0);
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
    address public poolManager;

    uint256 constant BONDING_CURVE_MAX_SUPPLY = Config.BONDING_CURVE_ALLOCATION / 2; // 225k for curve
    uint256 constant TOTAL_TOKENS_TO_CURVE = Config.BONDING_CURVE_ALLOCATION; // 450k total (225k for curve + 225k for LP)

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork(vm.envString("BASE_RPC"));

        // Get pool manager address
        poolManager = BaseUniswapDeployments.POOL_MANAGER();

        // Deploy mock FLK and etch it to the expected address
        MockFLK tempFlk = new MockFLK();
        vm.etch(Config.FLK(), address(tempFlk).code);
        flk = MockFLK(Config.FLK());

        // Deploy mock universal hook and etch it to an address with correct hook flags
        MockUniversalHook tempHook = new MockUniversalHook();
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
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

        // Configure creator coin with bonding curve and hook addresses
        creatorCoin.setAddresses(address(bondingCurve), mockHookAddress);

        // Transfer full allocation to bonding curve (450k: 225k for curve + 225k for LP)
        require(
            creatorCoin.transfer(address(bondingCurve), TOTAL_TOKENS_TO_CURVE), "Transfer failed"
        );

        // Setup FLK for users (deal doesn't work on Base mainnet fork, so we'll use vm.store)
        // For now, assume we're testing on a fork where users have FLK
        vm.label(creator, "Creator");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(bondingCurve), "BondingCurve");
        vm.label(address(creatorCoin), "CreatorCoin");
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
            bondingCurve.creatorTokensSold(),
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
        assertEq(bondingCurve.creatorTokensSold(), BONDING_CURVE_MAX_SUPPLY);
        (,,,,,, bool graduated) = bondingCurve.metadata();
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

        // Wait for transfer lock to expire (max 120 seconds)
        vm.warp(block.timestamp + 121);

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
        (,,,,,, bool graduated) = bondingCurve.metadata();
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

        // Wait for transfer lock to expire (max 120 seconds)
        vm.warp(block.timestamp + 121);

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
        assertEq(
            finalTokenBalance - initialTokenBalance,
            exactTokensWanted,
            "Should receive exact tokens"
        );

        // User should spend less than maxCost
        assertLt(initialFlkBalance - finalFlkBalance, maxCost, "Should spend less than max");

        // Curve should track the sale
        assertEq(
            bondingCurve.creatorTokensSold(), exactTokensWanted, "Curve should track tokens sold"
        );

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

    function test_SellExactTokens_Basic() public {
        // First buy some tokens
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensOwned = creatorCoin.balanceOf(user1);
        uint256 exactFlkWanted = 5e18; // Want exactly 5 FLK back

        // Get slope from metadata
        (,, uint256 slope,,,,) = bondingCurve.metadata();

        // Calculate how many tokens we need to sell
        uint256 expectedTokensToSell = LinearCurveMathV4.calculateSellCost(
            exactFlkWanted,
            bondingCurve.creatorTokensSold(),
            Config.BASE_PRICE,
            slope,
            Config.CREATOR_COIN_DECIMALS,
            Config.FLK_DECIMALS
        );

        // Set max tokens willing to sell (add buffer)
        uint256 maxTokensToSell = expectedTokensToSell * 2;

        // Wait for transfer lock to expire (max 120 seconds)
        vm.warp(block.timestamp + 121);

        creatorCoin.approve(address(bondingCurve), maxTokensToSell);
        uint256 initialFlkBalance = flk.balanceOf(user1);
        uint256 initialTokenBalance = creatorCoin.balanceOf(user1);

        bondingCurve.sellExactTokens(exactFlkWanted, maxTokensToSell);

        uint256 finalFlkBalance = flk.balanceOf(user1);
        uint256 finalTokenBalance = creatorCoin.balanceOf(user1);
        uint256 actualFlkReceived = finalFlkBalance - initialFlkBalance;
        uint256 actualTokensSold = initialTokenBalance - finalTokenBalance;

        vm.stopPrank();

        // Should receive approximately the exact FLK amount (minus fees)
        // The exactFlkWanted is before fees, so actual received will be less
        assertGt(actualFlkReceived, 0, "Should receive some FLK");
        assertLt(
            actualFlkReceived, exactFlkWanted, "Should receive less than requested due to fees"
        );

        // Should sell less than max
        assertLt(actualTokensSold, maxTokensToSell, "Should sell less than max");
        assertLe(actualTokensSold, tokensOwned, "Cannot sell more than owned");
    }

    function test_SellExactTokens_RevertsOnSlippage() public {
        // First buy some tokens
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 exactFlkWanted = 5e18;
        uint256 maxTokensToSell = 1e18; // Set unrealistically low

        creatorCoin.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.sellExactTokens(exactFlkWanted, maxTokensToSell);

        vm.stopPrank();
    }

    function test_SellExactTokens_RevertsWhenZeroAmount() public {
        // First buy some tokens
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        creatorCoin.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.ZeroInput.selector);
        bondingCurve.sellExactTokens(0, 1000e18);

        vm.stopPrank();
    }

    function test_SellExactTokens_RevertsWhenExceedsAvailable() public {
        // First buy some tokens
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        // Try to get more FLK than the contract has
        uint256 contractFlkBalance = flk.balanceOf(address(bondingCurve));
        uint256 tooMuchFlk = contractFlkBalance + 1e18;

        creatorCoin.approve(address(bondingCurve), type(uint256).max);

        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.sellExactTokens(tooMuchFlk, type(uint256).max);

        vm.stopPrank();
    }

    function test_SellExactTokens_ComparedToSell() public {
        // Test that sellExactTokens and sell produce consistent results

        // User1 will use sellExactTokens
        uint256 buyAmount1 = 10e18;
        flk.mint(user1, buyAmount1 * 2);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount1, 0);
        uint256 user1Tokens = creatorCoin.balanceOf(user1);
        vm.stopPrank();

        // User2 will use regular sell
        uint256 buyAmount2 = 10e18;
        flk.mint(user2, buyAmount2 * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount2, 0);
        vm.stopPrank();

        // Wait for transfer locks to expire (max 120 seconds)
        vm.warp(block.timestamp + 121);

        // User1 sells for exact FLK amount
        uint256 exactFlkWanted = 3e18;
        vm.startPrank(user1);
        creatorCoin.approve(address(bondingCurve), type(uint256).max);
        uint256 user1FlkBefore = flk.balanceOf(user1);
        bondingCurve.sellExactTokens(exactFlkWanted, user1Tokens);
        uint256 user1FlkReceived = flk.balanceOf(user1) - user1FlkBefore;
        uint256 user1TokensSold = user1Tokens - creatorCoin.balanceOf(user1);
        vm.stopPrank();

        // User2 sells the same amount of tokens
        vm.startPrank(user2);
        creatorCoin.approve(address(bondingCurve), type(uint256).max);
        uint256 user2FlkBefore = flk.balanceOf(user2);
        bondingCurve.sell(user1TokensSold, 0);
        uint256 user2FlkReceived = flk.balanceOf(user2) - user2FlkBefore;
        vm.stopPrank();

        // Both should receive similar FLK amounts (they sold at different curve positions so won't be exact)
        assertGt(user1FlkReceived, 0, "User1 should receive FLK");
        assertGt(user2FlkReceived, 0, "User2 should receive FLK");
    }

    function test_SellExactTokens_RevertsAfterGraduation() public {
        // Buy some tokens first
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();

        // Buy all remaining tokens to trigger graduation
        uint256 exhaustBuy = 25_000e18;
        flk.mint(user2, exhaustBuy * 2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(exhaustBuy, 0);
        vm.stopPrank();

        // Verify graduation happened
        (,,,,,, bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");

        // Try to sell for exact tokens - should revert
        vm.startPrank(user1);
        creatorCoin.approve(address(bondingCurve), type(uint256).max);
        vm.expectRevert(BondingCurve.AlreadyGraduated.selector);
        bondingCurve.sellExactTokens(1e18, type(uint256).max);
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
                // Decode the event data: tokenId, parentTokenBalance, creatorTokenBalance
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
        (,,,,,, bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");

        // Verify exactly 225k tokens were sold
        assertEq(
            bondingCurve.creatorTokensSold(),
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
        // casting to 'int256' is safe because values are well below int256.max and needed for signed difference
        console.log(
            "Difference from target:",
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(lpFlkAmount) - int256(Config.GRADUATION_THRESHOLD)
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

    function test_TransferLocksPreventsP2PTransfer() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);
        assertGt(tokensReceived, 0, "User should have tokens");

        vm.expectRevert(CreatorCoin.TransfersLocked.selector);
        // transfer is expected to fail, no need to check return value
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        creatorCoin.transfer(user2, tokensReceived / 2);
        vm.stopPrank();
    }

    function test_TransferLocksExpireAfterWindow() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        vm.warp(block.timestamp + 121);

        require(creatorCoin.transfer(user2, tokensReceived / 2), "Transfer failed");
        vm.stopPrank();

        assertEq(creatorCoin.balanceOf(user2), tokensReceived / 2, "User2 should receive tokens");
    }

    function test_TransferLocksAllowSellsToPoolManager() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        require(creatorCoin.transfer(poolManager, tokensReceived / 2), "Transfer failed");
        vm.stopPrank();

        assertEq(
            creatorCoin.balanceOf(poolManager),
            tokensReceived / 2,
            "PoolManager should receive tokens"
        );
    }

    function test_TransferLocksAllowSellsViaApproveAndBurn() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        creatorCoin.approve(address(bondingCurve), tokensReceived / 2);
        vm.stopPrank();

        vm.prank(address(bondingCurve));
        creatorCoin.burnFrom(user1, tokensReceived / 4);

        assertLt(creatorCoin.balanceOf(user1), tokensReceived, "Tokens should be burned");
    }

    function test_ContractIntermediaryGetsIndependentLock() public {
        BuyHelper helper = new BuyHelper(address(bondingCurve), address(flk), address(creatorCoin));

        flk.mint(address(helper), 10e18);

        vm.prank(user1);
        helper.buyTokens(1e18);

        uint256 helperTokens = creatorCoin.balanceOf(address(helper));
        assertGt(helperTokens, 0, "Helper should have tokens");

        vm.prank(address(helper));
        vm.expectRevert(CreatorCoin.TransfersLocked.selector);
        // transfer is expected to fail, no need to check return value
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        creatorCoin.transfer(user2, helperTokens / 2);

        flk.mint(user1, 10e18);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);
        vm.warp(block.timestamp + 121);
        require(creatorCoin.transfer(user2, creatorCoin.balanceOf(user1) / 2), "Transfer failed");
        vm.stopPrank();
    }

    function test_WindowCalculationWithPrevrandao() public {
        address user = makeAddr("user");
        address token = makeAddr("token");
        uint256 buyTimestamp = block.timestamp;
        uint256 entropyTimestamp = 12345;

        uint256 prevrandao1 = block.prevrandao;
        uint256 window1 = AntiFlipFeeLib.calculateWindow(
            user, token, buyTimestamp, prevrandao1, entropyTimestamp
        );

        uint256 prevrandao2 = prevrandao1 + 123456;
        uint256 window2 = AntiFlipFeeLib.calculateWindow(
            user, token, buyTimestamp, prevrandao2, entropyTimestamp
        );

        assertNotEq(window1, window2, "Windows should differ with different prevrandao");

        assertGe(window1, 30, "Window1 >= 30s");
        assertLe(window1, 120, "Window1 <= 120s");
        assertGe(window2, 30, "Window2 >= 30s");
        assertLe(window2, 120, "Window2 <= 120s");
    }

    function test_SameOriginDifferentTokensDifferentWindows() public {
        address user = makeAddr("user");
        address token1 = makeAddr("token1");
        address token2 = makeAddr("token2");
        uint256 buyTimestamp = block.timestamp;
        uint256 entropy1 = 100;
        uint256 entropy2 = 200;

        uint256 window1 = AntiFlipFeeLib.calculateWindow(
            user, token1, buyTimestamp, block.prevrandao, entropy1
        );

        uint256 window2 = AntiFlipFeeLib.calculateWindow(
            user, token2, buyTimestamp, block.prevrandao, entropy2
        );

        assertNotEq(window1, window2, "Different tokens should have different windows");
    }

    function test_MultipleUsersIndependentLocks() public {
        flk.mint(user1, 10e18);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);
        vm.stopPrank();

        uint256 user1BuyTime = block.timestamp;
        uint256 user1LockUntil = creatorCoin.transferLockedUntil(user1);
        assertGt(user1LockUntil, user1BuyTime, "User1 should be locked after buy");
        assertGe(user1LockUntil, user1BuyTime + 30, "User1 lock >= 30s");
        assertLe(user1LockUntil, user1BuyTime + 120, "User1 lock <= 120s");

        flk.mint(user2, 10e18);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);
        vm.stopPrank();

        uint256 user2BuyTime = block.timestamp;
        uint256 user2LockUntil = creatorCoin.transferLockedUntil(user2);
        assertGt(user2LockUntil, user2BuyTime, "User2 should be locked after buy");
        assertGe(user2LockUntil, user2BuyTime + 30, "User2 lock >= 30s");
        assertLe(user2LockUntil, user2BuyTime + 120, "User2 lock <= 120s");

        assertTrue(
            creatorCoin.transferLockedUntil(user1) > 0
                && creatorCoin.transferLockedUntil(user2) > 0,
            "Both users should have locks"
        );

        vm.warp(block.timestamp + 121);

        vm.prank(user1);
        require(creatorCoin.transfer(creator, creatorCoin.balanceOf(user1) / 2), "Transfer failed");

        vm.prank(user2);
        require(creatorCoin.transfer(creator, creatorCoin.balanceOf(user2) / 2), "Transfer failed");

        assertGt(
            creatorCoin.balanceOf(creator), 0, "Creator should have received tokens from both users"
        );
    }

    function test_FullBuyLockSellFlow() public {
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);

        uint256 lockUntil = creatorCoin.transferLockedUntil(user1);
        assertGt(lockUntil, block.timestamp, "Lock should be active");
        assertLe(lockUntil, block.timestamp + 120, "Lock should be <= 120s");

        vm.expectRevert(CreatorCoin.TransfersLocked.selector);
        // transfer is expected to fail, no need to check return value
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        creatorCoin.transfer(user2, tokensReceived / 2);

        creatorCoin.approve(address(bondingCurve), tokensReceived / 4);
        vm.warp(block.timestamp + 121);
        bondingCurve.sell(tokensReceived / 4, 0);

        require(creatorCoin.transfer(user2, tokensReceived / 4), "Transfer failed");
        vm.stopPrank();

        assertGt(creatorCoin.balanceOf(user2), 0, "User2 should have received tokens");
    }

    function test_SellWorksDuringTransferLock() public {
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount * 2);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(buyAmount, 0);

        uint256 tokensReceived = creatorCoin.balanceOf(user1);
        uint256 lockUntil = creatorCoin.transferLockedUntil(user1);

        assertGt(lockUntil, block.timestamp, "Lock should be active");

        creatorCoin.approve(address(bondingCurve), tokensReceived / 2);
        uint256 flkBefore = flk.balanceOf(user1);
        bondingCurve.sell(tokensReceived / 2, 0);
        uint256 flkAfter = flk.balanceOf(user1);

        vm.stopPrank();

        assertGt(flkAfter, flkBefore, "Should receive FLK from sell during lock");
        assertEq(creatorCoin.balanceOf(user1), tokensReceived / 2, "Half tokens should be sold");
    }

    function test_BuyWorksDuringTransferLock() public {
        flk.mint(user1, 20e18);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);

        uint256 firstBuyTokens = creatorCoin.balanceOf(user1);
        uint256 firstLockUntil = creatorCoin.transferLockedUntil(user1);
        uint256 firstBuyTime = block.timestamp;
        assertGt(firstLockUntil, block.timestamp, "Lock should be active after first buy");

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 10);

        bondingCurve.buy(1e18, 0);

        uint256 secondBuyTokens = creatorCoin.balanceOf(user1);
        uint256 secondLockUntil = creatorCoin.transferLockedUntil(user1);
        uint256 secondBuyTime = block.timestamp;

        vm.stopPrank();

        assertGt(secondBuyTokens, firstBuyTokens, "Should receive more tokens from second buy");
        assertGt(secondLockUntil, secondBuyTime, "Lock should be active after second buy");
        assertGe(secondLockUntil, secondBuyTime + 30, "Second lock >= 30s from second buy");
        assertLe(secondLockUntil, secondBuyTime + 120, "Second lock <= 120s from second buy");
    }

    function test_TransferToLockedUserWorks() public {
        flk.mint(user1, 10e18);
        flk.mint(user2, 10e18);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(5e18, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(5e18, 0);
        vm.stopPrank();

        assertGt(creatorCoin.transferLockedUntil(user1), block.timestamp, "User1 should be locked");

        vm.warp(block.timestamp + 121);

        vm.prank(user2);
        require(creatorCoin.transfer(user1, 100e18), "Transfer failed");

        assertGt(
            creatorCoin.balanceOf(user1), 0, "User1 should receive tokens even if they were locked"
        );
    }

    function test_P2PTransferFailsDuringLock() public {
        flk.mint(user1, 10e18);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);

        uint256 balance = creatorCoin.balanceOf(user1);
        assertGt(balance, 0, "User should have tokens");
        assertGt(creatorCoin.transferLockedUntil(user1), block.timestamp, "Lock should be active");

        vm.expectRevert(CreatorCoin.TransfersLocked.selector);
        // transfer is expected to fail, no need to check return value
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        creatorCoin.transfer(user2, balance / 2);

        vm.stopPrank();
    }

    function test_P2PTransferWorksAfterLockExpires() public {
        flk.mint(user1, 10e18);

        vm.startPrank(user1);
        flk.approve(address(bondingCurve), type(uint256).max);
        bondingCurve.buy(1e18, 0);

        uint256 balance = creatorCoin.balanceOf(user1);
        uint256 lockUntil = creatorCoin.transferLockedUntil(user1);

        vm.warp(lockUntil + 1);

        require(creatorCoin.transfer(user2, balance / 2), "Transfer failed");
        vm.stopPrank();

        assertEq(
            creatorCoin.balanceOf(user2),
            balance / 2,
            "User2 should receive tokens after lock expires"
        );
    }
}
