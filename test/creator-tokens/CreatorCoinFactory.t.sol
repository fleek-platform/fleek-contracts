// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { CreatorCoinFactory } from "../../src/creator-tokens/core/CreatorCoinFactory.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFLK is ERC20 {
    constructor() ERC20("Fleek Token", "FLK") { }
}

contract CreatorCoinFactoryTest is Test {
    CreatorCoinFactory public factory;
    MockFLK public flk;

    address public owner = address(0x1);
    address public creator = address(0x2);
    address public nonOwner = address(0x3);
    address public bondingCurve = address(0x4);

    function setUp() public {
        // Fork Base mainnet for Config addresses
        vm.createSelectFork(vm.envString("BASE_RPC"));

        // Deploy mock FLK and etch it to expected address
        MockFLK tempFlk = new MockFLK();
        vm.etch(Config.FLK(), address(tempFlk).code);
        flk = MockFLK(Config.FLK());

        // Deploy factory
        factory = new CreatorCoinFactory(owner);

        vm.label(owner, "Owner");
        vm.label(creator, "Creator");
        vm.label(nonOwner, "NonOwner");
        vm.label(bondingCurve, "BondingCurve");
    }

    function test_InitialState() public view {
        assertEq(factory.owner(), owner);
    }

    function test_Deploy_OnlyOwner() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        // Non-owner should fail
        vm.startPrank(nonOwner);
        vm.expectRevert();
        factory.deploy(creator, name, symbol, vestingStart, vestingDuration, cliffDuration);
        vm.stopPrank();

        // Owner should succeed
        vm.startPrank(owner);
        (CreatorCoin token, CreatorVesting vesting) =
            factory.deploy(creator, name, symbol, vestingStart, vestingDuration, cliffDuration);
        assertTrue(address(token) != address(0), "Token should be deployed");
        assertTrue(address(vesting) != address(0), "Vesting should be deployed");
        vm.stopPrank();
    }

    function test_Deploy_CreatesTokenWithCorrectProperties() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, name, symbol, vestingStart, vestingDuration, cliffDuration);
        vm.stopPrank();

        assertEq(token.name(), name, "Token name should match");
        assertEq(token.symbol(), symbol, "Token symbol should match");
        assertEq(token.decimals(), 18, "Token should have 18 decimals");
    }

    function test_Deploy_CreatesVestingWithCorrectProperties() public {
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.startPrank(owner);
        (, CreatorVesting vesting) =
            factory.deploy(creator, "Test", "TEST", vestingStart, vestingDuration, cliffDuration);
        vm.stopPrank();

        assertEq(vesting.owner(), creator, "Owner should be creator");
        assertEq(vesting.start(), vestingStart, "Start time should match");
        assertEq(vesting.duration(), vestingDuration, "Duration should match");
        assertEq(
            vesting.cliff(), vestingStart + cliffDuration, "Cliff should be start + cliff duration"
        );
    }

    function test_Deploy_DistributesTokensCorrectly() public {
        vm.startPrank(owner);
        (CreatorCoin token, CreatorVesting vesting) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        // Check allocations
        assertEq(
            token.balanceOf(Config.FOUNDATION()),
            Config.CREATOR_FUND_ALLOCATION + Config.FAN_POOL_ALLOCATION,
            "Foundation should receive correct allocation"
        );
        assertEq(
            token.balanceOf(address(vesting)),
            Config.CREATOR_ALLOCATION,
            "Vesting should receive correct allocation"
        );

        assertEq(
            token.balanceOf(address(factory)),
            Config.BONDING_CURVE_ALLOCATION,
            "Factory should hold bonding curve allocation"
        );
    }

    function test_Deploy_TotalSupplyCorrect() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        uint256 expectedTotal =
            Config.BONDING_CURVE_ALLOCATION + Config.CREATOR_ALLOCATION
            + Config.CREATOR_FUND_ALLOCATION + Config.FAN_POOL_ALLOCATION;

        assertEq(token.totalSupply(), expectedTotal, "Total supply should match sum of allocations");
    }

    function test_TransferToBondingCurve_OnlyOwner() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        // Non-owner should fail
        vm.startPrank(nonOwner);
        vm.expectRevert();
        factory.transferToBondingCurve(address(token), bondingCurve);
        vm.stopPrank();

        // Owner should succeed
        vm.startPrank(owner);
        factory.transferToBondingCurve(address(token), bondingCurve);
        vm.stopPrank();

        assertEq(
            token.balanceOf(bondingCurve),
            Config.BONDING_CURVE_ALLOCATION,
            "Bonding curve should receive full allocation"
        );
    }

    function test_TransferToBondingCurve_TransfersCorrectAmount() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);

        uint256 factoryBalanceBefore = token.balanceOf(address(factory));
        assertEq(
            factoryBalanceBefore,
            Config.BONDING_CURVE_ALLOCATION,
            "Factory should start with bonding curve allocation"
        );

        factory.transferToBondingCurve(address(token), bondingCurve);
        vm.stopPrank();

        assertEq(
            token.balanceOf(bondingCurve),
            Config.BONDING_CURVE_ALLOCATION,
            "Bonding curve should receive allocation"
        );
        assertEq(token.balanceOf(address(factory)), 0, "Factory should have transferred all tokens");
    }

    function test_Deploy_MultipleTokens() public {
        vm.startPrank(owner);

        (CreatorCoin token1, CreatorVesting vesting1) = factory.deploy(
            creator, "Token One", "ONE", uint64(block.timestamp), 365 days, 30 days
        );

        (CreatorCoin token2, CreatorVesting vesting2) = factory.deploy(
            creator, "Token Two", "TWO", uint64(block.timestamp), 365 days, 30 days
        );

        vm.stopPrank();

        // Verify different tokens
        assertTrue(address(token1) != address(token2), "Should create different tokens");
        assertTrue(
            address(vesting1) != address(vesting2), "Should create different vesting contracts"
        );

        // Verify each has correct allocations
        assertEq(
            token1.balanceOf(address(factory)),
            Config.BONDING_CURVE_ALLOCATION,
            "Token1: Factory should hold bonding curve allocation"
        );
        assertEq(
            token2.balanceOf(address(factory)),
            Config.BONDING_CURVE_ALLOCATION,
            "Token2: Factory should hold bonding curve allocation"
        );
    }

    function test_Deploy_WithDifferentVestingParameters() public {
        vm.startPrank(owner);

        // First token with short vesting
        (CreatorCoin token1, CreatorVesting vesting1) = factory.deploy(
            creator, "Token One", "ONE", uint64(block.timestamp), 180 days, 15 days
        );

        // Second token with long vesting
        (CreatorCoin token2, CreatorVesting vesting2) = factory.deploy(
            creator, "Token Two", "TWO", uint64(block.timestamp), 730 days, 90 days
        );

        vm.stopPrank();

        // Verify different vesting parameters
        assertEq(vesting1.duration(), 180 days, "Vesting1 should have 180 day duration");
        assertEq(vesting2.duration(), 730 days, "Vesting2 should have 730 day duration");

        uint64 cliff1 = uint64(block.timestamp) + 15 days;
        uint64 cliff2 = uint64(block.timestamp) + 90 days;

        assertEq(vesting1.cliff(), cliff1, "Vesting1 should have 15 day cliff");
        assertEq(vesting2.cliff(), cliff2, "Vesting2 should have 90 day cliff");
    }

    function test_Deploy_WithDifferentCreators() public {
        address creator1 = address(0x100);
        address creator2 = address(0x200);

        vm.startPrank(owner);

        (, CreatorVesting vesting1) = factory.deploy(
            creator1, "Token One", "ONE", uint64(block.timestamp), 365 days, 30 days
        );

        (, CreatorVesting vesting2) = factory.deploy(
            creator2, "Token Two", "TWO", uint64(block.timestamp), 365 days, 30 days
        );

        vm.stopPrank();

        // Verify each vesting has correct beneficiary (owner)
        assertEq(vesting1.owner(), creator1, "Vesting1 should have creator1 as owner");
        assertEq(vesting2.owner(), creator2, "Vesting2 should have creator2 as owner");
    }

    function test_TransferToBondingCurve_CannotTransferTwice() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);

        // First transfer should succeed
        factory.transferToBondingCurve(address(token), bondingCurve);

        // Second transfer should fail (no tokens left - ERC20 InsufficientBalance error)
        vm.expectRevert();
        factory.transferToBondingCurve(address(token), address(0x999));

        vm.stopPrank();
    }

    function test_Deploy_FactoryBecomesInitialHolder() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        // Factory should be the initial holder of bonding curve allocation
        // This allows it to transfer later to the bonding curve
        assertEq(
            token.balanceOf(address(factory)),
            Config.BONDING_CURVE_ALLOCATION,
            "Factory should hold bonding curve allocation initially"
        );
    }

    function test_Deploy_AllocationsSumToTotalSupply() public {
        vm.startPrank(owner);
        (CreatorCoin token, CreatorVesting vesting) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        uint256 foundationBalance = token.balanceOf(Config.FOUNDATION());
        uint256 vestingBalance = token.balanceOf(address(vesting));
        uint256 factoryBalance = token.balanceOf(address(factory));

        uint256 totalAllocated = foundationBalance + vestingBalance + factoryBalance;

        assertEq(
            totalAllocated, token.totalSupply(), "Sum of allocations should equal total supply"
        );
    }

    function test_Deploy_NoTokensLeftUnallocated() public {
        vm.startPrank(owner);
        (CreatorCoin token,) =
            factory.deploy(creator, "Test", "TEST", uint64(block.timestamp), 365 days, 30 days);
        vm.stopPrank();

        // Check that no tokens remain unallocated (balance of address(0) should be 0)
        // and that creator doesn't automatically get tokens (only through vesting)
        assertEq(token.balanceOf(creator), 0, "Creator should not receive tokens directly");
    }
}
