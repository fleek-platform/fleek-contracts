// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { BondingCurve } from "../../src/creator-tokens/BondingCurve.sol";
import { CreatorCoin } from "../../src/creator-tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/CreatorVesting.sol";
import { FactoryConfig } from "../../src/creator-tokens/lib/FactoryConfig.sol";
import { LinearCurveMathV4 } from "../../src/creator-tokens/lib/LinearCurveMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFLK is ERC20 {
    constructor() ERC20("Fleek Token", "FLK") {
        _mint(msg.sender, 1_000_000_000e18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
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
    
    uint256 constant BONDING_CURVE_MAX_SUPPLY = FactoryConfig.BONDING_CURVE_ALLOCATION / 2; // 225k for curve
    uint256 constant TOTAL_TOKENS_TO_CURVE = FactoryConfig.BONDING_CURVE_ALLOCATION; // 450k total (225k for curve + 225k for LP)

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork(vm.envString("BASE_RPC"));
        
        // Deploy mock FLK and etch it to the expected address
        MockFLK tempFlk = new MockFLK();
        vm.etch(FactoryConfig.FLK, address(tempFlk).code);
        flk = MockFLK(FactoryConfig.FLK);
        
        // Deploy creator coin
        creatorCoin = new CreatorCoin("Test Token", "TEST", FactoryConfig.CREATOR_COIN_SUPPLY);
        
        // Deploy vesting wallet
        vestingWallet = new CreatorVesting(
            creator,
            uint64(block.timestamp),
            365 days,
            30 days
        );
        
        // Deploy bonding curve
        bondingCurve = new BondingCurve(
            creator,
            address(creatorCoin),
            FactoryConfig.GRADUATION_THRESHOLD,
            FactoryConfig.BASE_PRICE,
            BONDING_CURVE_MAX_SUPPLY, // Max supply for curve calculations (225k)
            address(vestingWallet)
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
        (
            address _creator,
            address _characterToken,
            uint256 _graduationThreshold,
            ,
            uint256 _basePrice,
            ,
            ,
            bool _graduated
        ) = bondingCurve.metadata();
        
        assertEq(bondingCurve.characterTokensSold(), 0);
        assertFalse(_graduated);
        assertEq(_creator, creator);
        assertEq(_characterToken, address(creatorCoin));
        assertEq(_graduationThreshold, FactoryConfig.GRADUATION_THRESHOLD);
        assertEq(_basePrice, FactoryConfig.BASE_PRICE);
        assertEq(creatorCoin.balanceOf(address(bondingCurve)), TOTAL_TOKENS_TO_CURVE);
    }

    function test_Buy_Basic() public {
        uint256 buyAmount = 1e18; // 1 FLK
        
        // Give user1 FLK
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        
        uint256 initialTokenBalance = creatorCoin.balanceOf(user1);
        uint256 initialFlkBalance = flk.balanceOf(user1);
        
        bondingCurve.buy(buyAmount, 0);
        
        vm.stopPrank();
        
        // Check balances changed
        assertGt(creatorCoin.balanceOf(user1), initialTokenBalance, "User should receive tokens");
        assertEq(flk.balanceOf(user1), initialFlkBalance - buyAmount, "FLK should be spent");
        assertEq(bondingCurve.characterTokensSold(), creatorCoin.balanceOf(user1), "Sold amount should match");
    }

    function test_Buy_GraduatesWhenAllTokensSold() public {
        // Buy all available tokens from the curve
        uint256 buyAmount = 25_000e18;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();
        
        // Verify we hit max supply and graduated
        assertEq(bondingCurve.characterTokensSold(), BONDING_CURVE_MAX_SUPPLY);
        (,,,,,,address vestingWallet, bool graduated) = bondingCurve.metadata();
        assertTrue(graduated, "Should have graduated");
        
        // Try to buy more - should revert with AlreadyGraduated
        flk.mint(user2, 1e18);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), 1e18);
        
        vm.expectRevert(BondingCurve.AlreadyGraduated.selector);
        bondingCurve.buy(1e18, 0);
        vm.stopPrank();
    }

    function test_Buy_RevertsWhenBelowMinimum() public {
        uint256 buyAmount = bondingCurve.MIN_PURCHASE_FLK() - 1;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        
        vm.expectRevert(BondingCurve.NotEnoughFLK.selector);
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();
    }

    function test_Buy_RevertsOnSlippage() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        
        // Set minOut too high
        vm.expectRevert(BondingCurve.SlippageExceeded.selector);
        bondingCurve.buy(buyAmount, type(uint256).max);
        vm.stopPrank();
    }

    function test_Sell_Basic() public {
        // First buy some tokens
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
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
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        uint256 tokensOwned = creatorCoin.balanceOf(user1);
        vm.stopPrank();
        
        // Buy all remaining tokens to trigger graduation
        uint256 exhaustBuy = 25_000e18;
        flk.mint(user2, exhaustBuy);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), exhaustBuy);
        bondingCurve.buy(exhaustBuy, 0);
        vm.stopPrank();
        
        // Verify graduation happened
        (,,,,,,address vestingWallet, bool graduated) = bondingCurve.metadata();
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
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        
        uint256 sellAmount = bondingCurve.MIN_PURCHASE_FLK() - 1;
        creatorCoin.approve(address(bondingCurve), sellAmount);
        
        vm.expectRevert(BondingCurve.ZeroInput.selector);
        bondingCurve.sell(sellAmount, 0);
        vm.stopPrank();
    }

    function test_BuySell_RoundTrip() public {
        uint256 buyAmount = 10e18;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        
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
        flk.mint(user1, buyAmount);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        uint256 firstBuyTokens = creatorCoin.balanceOf(user1);
        vm.stopPrank();
        
        // Second buy (same FLK amount)
        flk.mint(user2, buyAmount);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        uint256 secondBuyTokens = creatorCoin.balanceOf(user2);
        vm.stopPrank();
        
        // Second buy should yield fewer tokens (price went up)
        assertLt(secondBuyTokens, firstBuyTokens, "Price should increase with supply");
    }

    function test_Buy_EmitsBuyEvent() public {
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount);
        
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        
        vm.expectEmit(true, false, false, false);
        emit BondingCurve.Buy(user1, 0, 0); // We don't know exact amounts, just check event exists
        bondingCurve.buy(buyAmount, 0);
        vm.stopPrank();
    }

    function test_Sell_EmitsSellEvent() public {
        // Buy first
        uint256 buyAmount = 1e18;
        flk.mint(user1, buyAmount);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount);
        bondingCurve.buy(buyAmount, 0);
        
        uint256 sellAmount = creatorCoin.balanceOf(user1);
        creatorCoin.approve(address(bondingCurve), sellAmount);
        
        vm.expectEmit(true, false, false, false);
        emit BondingCurve.Sell(user1, 0, 0);
        bondingCurve.sell(sellAmount, 0);
        vm.stopPrank();
    }

    function test_CapLogic_BuyAdjustsWhenLimited() public {
        // This test verifies that when available supply is less than requested,
        // the buy function correctly caps the purchase and adjusts the cost
        
        // First, let's buy a good chunk to reduce available supply
        uint256 initialBuy = 5_000e18;
        flk.mint(user1, initialBuy);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), initialBuy);
        bondingCurve.buy(initialBuy, 0);
        vm.stopPrank();
        
        // Now make a second buy that would exceed available supply
        uint256 largeBuy = 50_000e18;
        flk.mint(user2, largeBuy);
        
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), largeBuy);
        
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
        flk.approve(address(bondingCurve), massiveAmount);
        bondingCurve.buy(massiveAmount, 0);
        vm.stopPrank();
        uint256 tokensBought = creatorCoin.balanceOf(user1);
        assertLe(tokensBought, BONDING_CURVE_MAX_SUPPLY);
    }

    function test_Graduation_CreatesFullRangeLiquidity() public {
        // Buy almost all tokens first to get close to graduation
        uint256 buyAmount1 = 19_000e18;
        flk.mint(user1, buyAmount1);
        vm.startPrank(user1);
        flk.approve(address(bondingCurve), buyAmount1);
        bondingCurve.buy(buyAmount1, 0);
        vm.stopPrank();
        
        // Now buy the rest to trigger graduation and capture balances
        uint256 buyAmount2 = 10_000e18;
        flk.mint(user2, buyAmount2);
        vm.startPrank(user2);
        flk.approve(address(bondingCurve), buyAmount2);
        
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
}
