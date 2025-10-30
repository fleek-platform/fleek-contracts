// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { BalanceDelta } from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {
    UniversalAntiFlipFeeHook
} from "../../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { AntiFlipFeeLib } from "../../src/creator-tokens/libraries/AntiFlipFeeLib.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { MockERC20 } from "solmate/src/test/utils/mocks/MockERC20.sol";

/**
 * @title UniversalAntiFlipFeeHookTest
 * @notice Streamlined test suite for the UniversalAntiFlipFeeHook contract
 * @dev Tests core functionality: registration, fees, windows, claiming, and multi-token support
 */
contract UniversalAntiFlipFeeHookTest is Test {
    // Core contracts
    UniversalAntiFlipFeeHook public hook;
    MockFactory public factory;
    MockPoolManager public mockPoolManager;

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
    address public foundation; // Will be set in setUp after chainId is set

    // Pool configuration
    PoolKey public poolKey;
    uint160 internal constant MIN_PRICE_LIMIT = 4295128740;
    uint160 internal constant MAX_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    function setUp() public {
        // Set chainid to Base Sepolia for testing
        vm.chainId(84532);

        // Now set foundation address after chain ID is correct
        foundation = Config.FOUNDATION();

        // Deploy FLK token at the expected address for Base Sepolia
        flk = new MockERC20("Fleek", "FLK", 18);
        vm.etch(Config.FLK(), address(flk).code);

        // Deploy mock factory
        factory = new MockFactory();

        // Deploy mock pool manager
        mockPoolManager = new MockPoolManager();

        // Deploy hook at correct address with afterSwap permissions
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
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

        vestingWallet1 = new CreatorVesting(creator1, uint64(block.timestamp), 365 days, 30 days);

        vm.prank(creator1);
        creatorToken1.transfer(address(vestingWallet1), 100_000e18);

        // Deploy creator 2 token and vesting
        vm.prank(creator2);
        creatorToken2 = new CreatorCoin("Creator Token 2", "CT2");

        vestingWallet2 = new CreatorVesting(creator2, uint64(block.timestamp), 365 days, 30 days);

        vm.prank(creator2);
        creatorToken2.transfer(address(vestingWallet2), 100_000e18);

        // Register token1 with factory (simulate bonding curve registering)
        factory.registerToken(address(creatorToken1), address(this));

        // Register token2 with factory
        factory.registerToken(address(creatorToken2), makeAddr("bondingCurve2"));

        // Setup pool key for tests
        address flkAddress = Config.FLK();
        bool flkIsToken0 = flkAddress < address(creatorToken1);
        poolKey = PoolKey({
            currency0: Currency.wrap(flkIsToken0 ? flkAddress : address(creatorToken1)),
            currency1: Currency.wrap(flkIsToken0 ? address(creatorToken1) : flkAddress),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    /*//////////////////////////////////////////////////////////////
                         CORE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_HookPermissions() public view {
        // Verify hook has correct permissions for afterSwap operations
        Hooks.Permissions memory permissions = hook.getHookPermissions();

        assertTrue(permissions.afterSwap, "afterSwap should be true");
        assertTrue(permissions.afterSwapReturnDelta, "afterSwapReturnDelta should be true");
        assertFalse(permissions.beforeSwap, "beforeSwap should be false");
    }

    function test_TokenRegistration() public {
        // Test successful token registration
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));

        assertEq(
            hook.tokenToCreator(address(creatorToken1)), creator1, "Creator should be registered"
        );
        assertEq(
            hook.tokenToVestingWallet(address(creatorToken1)),
            address(vestingWallet1),
            "Vesting wallet should be registered"
        );

        // Test registration protection
        vm.expectRevert(UniversalAntiFlipFeeHook.TokenAlreadyRegistered.selector);
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));

        // Test unauthorized registration
        address fakeToken = makeAddr("fakeToken");
        vm.expectRevert(UniversalAntiFlipFeeHook.NotAuthorizedBondingCurve.selector);
        hook.registerToken(fakeToken, creator1, address(vestingWallet1));
    }

    function test_WindowBasedFees() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));

        // Setup user
        MockERC20(Config.FLK()).mint(user1, 10000e18);
        vm.prank(user1);
        MockERC20(Config.FLK()).approve(address(hook), type(uint256).max);

        // Execute buy
        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == Config.FLK();
        SwapParams memory buyParams = SwapParams({
            zeroForOne: flkIsToken0, amountSpecified: -1000e18, sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), abi.encodePacked(user1));

        // Verify buy timestamp recorded
        uint256 buyTime = hook.userLastBuy(address(creatorToken1), user1);
        assertGt(buyTime, 0, "Buy timestamp should be recorded");

        // Calculate user's specific window
        uint256 window = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            buyTime,
            hook.tokenGraduationTimestamp(address(creatorToken1))
        );
        assertGe(window, 30, "Window should be at least 30s");
        assertLe(window, 120, "Window should be at most 120s");

        // Test sell within window - should charge 12%
        vm.warp(buyTime + window - 1);
        SwapParams memory sellParams = SwapParams({
            zeroForOne: !flkIsToken0,
            amountSpecified: -100e18,
            sqrtPriceLimitX96: flkIsToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT
        });

        uint256 hookBalanceBefore = MockERC20(Config.FLK()).balanceOf(address(hook));
        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, sellParams, BalanceDelta.wrap(0), abi.encodePacked(user1));
        uint256 feeWithinWindow =
            MockERC20(Config.FLK()).balanceOf(address(hook)) - hookBalanceBefore;

        // Test sell after window - should charge 2%
        vm.warp(buyTime + window + 1);
        hookBalanceBefore = MockERC20(Config.FLK()).balanceOf(address(hook));
        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, sellParams, BalanceDelta.wrap(0), abi.encodePacked(user1));
        uint256 feeAfterWindow =
            MockERC20(Config.FLK()).balanceOf(address(hook)) - hookBalanceBefore;

        // Verify fees
        assertEq(feeWithinWindow, (100e18 * 1200) / 10000, "Should charge 12% within window");
        assertEq(feeAfterWindow, (100e18 * 200) / 10000, "Should charge 2% after window");
    }

    function test_PerTokenIndependentTracking() public {
        // Register both tokens
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        vm.prank(makeAddr("bondingCurve2"));
        hook.registerToken(address(creatorToken2), creator2, address(vestingWallet2));

        // Setup user
        MockERC20(Config.FLK()).mint(user1, 20000e18);
        vm.prank(user1);
        MockERC20(Config.FLK()).approve(address(hook), type(uint256).max);

        // Buy Token1
        bool flkIsToken0_1 = Currency.unwrap(poolKey.currency0) == Config.FLK();
        SwapParams memory buyParams1 = SwapParams({
            zeroForOne: flkIsToken0_1, amountSpecified: -1000e18, sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, buyParams1, BalanceDelta.wrap(0), abi.encodePacked(user1));

        // Create pool key and buy Token2
        bool flkIsToken0_2 = Config.FLK() < address(creatorToken2);
        PoolKey memory poolKey2 = PoolKey({
            currency0: Currency.wrap(flkIsToken0_2 ? Config.FLK() : address(creatorToken2)),
            currency1: Currency.wrap(flkIsToken0_2 ? address(creatorToken2) : Config.FLK()),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        SwapParams memory buyParams2 = SwapParams({
            zeroForOne: flkIsToken0_2, amountSpecified: -1000e18, sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey2, buyParams2, BalanceDelta.wrap(0), abi.encodePacked(user1));

        // Verify both timestamps are recorded independently
        uint256 buyTime = block.timestamp;
        assertEq(hook.userLastBuy(address(creatorToken1), user1), buyTime, "Token1 buy recorded");
        assertEq(hook.userLastBuy(address(creatorToken2), user1), buyTime, "Token2 buy recorded");

        // Verify windows are independent
        uint256 window1 = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            buyTime,
            hook.tokenGraduationTimestamp(address(creatorToken1))
        );
        uint256 window2 = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken2),
            buyTime,
            hook.tokenGraduationTimestamp(address(creatorToken2))
        );

        // Windows should be valid but potentially different
        assertGe(window1, 30, "Token1 window >= 30s");
        assertLe(window1, 120, "Token1 window <= 120s");
        assertGe(window2, 30, "Token2 window >= 30s");
        assertLe(window2, 120, "Token2 window <= 120s");
    }

    function test_FeeClaiming() public {
        // Register token
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));

        // Execute trades to generate fees
        MockERC20(Config.FLK()).mint(user1, 10000e18);
        vm.prank(user1);
        MockERC20(Config.FLK()).approve(address(hook), type(uint256).max);

        bool flkIsToken0 = Currency.unwrap(poolKey.currency0) == Config.FLK();
        SwapParams memory buyParams = SwapParams({
            zeroForOne: flkIsToken0, amountSpecified: -1000e18, sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user1, poolKey, buyParams, BalanceDelta.wrap(0), abi.encodePacked(user1));

        // Check fees accumulated (2% of 1000 = 20 FLK)
        uint256 totalFee = (1000e18 * 200) / 10000;
        (uint256 foundationBps, uint256 creatorBps) =
            AntiFlipFeeLib.getFeeRates(creator1, address(creatorToken1), address(vestingWallet1));

        uint256 foundationFee = (totalFee * foundationBps) / (foundationBps + creatorBps);
        uint256 creatorFee = totalFee - foundationFee;

        assertEq(hook.claimableFees(foundation), foundationFee, "Foundation fees accumulated");
        assertEq(hook.claimableFees(creator1), creatorFee, "Creator fees accumulated");

        // Fund hook and claim fees
        MockERC20(Config.FLK()).mint(address(hook), totalFee);

        uint256 foundationBalanceBefore = MockERC20(Config.FLK()).balanceOf(foundation);
        vm.prank(foundation);
        hook.claimFees();
        assertEq(
            MockERC20(Config.FLK()).balanceOf(foundation) - foundationBalanceBefore,
            foundationFee,
            "Foundation claimed fees"
        );

        uint256 creatorBalanceBefore = MockERC20(Config.FLK()).balanceOf(creator1);
        vm.prank(creator1);
        hook.claimFees();
        assertEq(
            MockERC20(Config.FLK()).balanceOf(creator1) - creatorBalanceBefore,
            creatorFee,
            "Creator claimed fees"
        );

        // Verify can't claim twice
        vm.expectRevert(UniversalAntiFlipFeeHook.NoFeesToClaim.selector);
        vm.prank(creator1);
        hook.claimFees();
    }

    function test_Integration_FullFlow() public {
        // Register both tokens
        hook.registerToken(address(creatorToken1), creator1, address(vestingWallet1));
        vm.prank(makeAddr("bondingCurve2"));
        hook.registerToken(address(creatorToken2), creator2, address(vestingWallet2));

        // Setup users
        MockERC20(Config.FLK()).mint(user1, 50000e18);
        MockERC20(Config.FLK()).mint(user2, 50000e18);
        vm.prank(user1);
        MockERC20(Config.FLK()).approve(address(hook), type(uint256).max);
        vm.prank(user2);
        MockERC20(Config.FLK()).approve(address(hook), type(uint256).max);

        // User1 buys Token1
        _executeBuySwap(user1, poolKey, 5000e18);
        uint256 user1BuyTime = block.timestamp;

        // User2 buys Token2
        PoolKey memory poolKey2 = _createPoolKey2();
        _executeBuySwap(user2, poolKey2, 3000e18);

        // Calculate user1's window
        uint256 user1Window = AntiFlipFeeLib.calculateWindow(
            user1,
            address(creatorToken1),
            user1BuyTime,
            hook.tokenGraduationTimestamp(address(creatorToken1))
        );

        // User1 sells within window (high fee)
        vm.warp(block.timestamp + user1Window / 2);
        _executeSellSwap(user1, poolKey, 1000e18);

        // User2 sells after window (normal fee)
        vm.warp(block.timestamp + 150);
        _executeSellSwap(user2, poolKey2, 1000e18);

        // Verify fees accumulated for all parties
        assertGt(hook.claimableFees(foundation), 0, "Foundation has fees");
        assertGt(hook.claimableFees(creator1), 0, "Creator1 has fees");
        assertGt(hook.claimableFees(creator2), 0, "Creator2 has fees");

        // Claim all fees
        uint256 totalFees =
            hook.claimableFees(foundation) + hook.claimableFees(creator1)
            + hook.claimableFees(creator2);
        MockERC20(Config.FLK()).mint(address(hook), totalFees);

        vm.prank(foundation);
        hook.claimFees();
        vm.prank(creator1);
        hook.claimFees();
        vm.prank(creator2);
        hook.claimFees();

        // Verify all claimed
        assertEq(hook.claimableFees(foundation), 0, "Foundation claimed all");
        assertEq(hook.claimableFees(creator1), 0, "Creator1 claimed all");
        assertEq(hook.claimableFees(creator2), 0, "Creator2 claimed all");
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createPoolKey2() internal view returns (PoolKey memory) {
        bool flkIsToken0 = Config.FLK() < address(creatorToken2);
        return PoolKey({
            currency0: Currency.wrap(flkIsToken0 ? Config.FLK() : address(creatorToken2)),
            currency1: Currency.wrap(flkIsToken0 ? address(creatorToken2) : Config.FLK()),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _executeBuySwap(address user, PoolKey memory key, uint256 amount) internal {
        bool flkIsToken0 = Currency.unwrap(key.currency0) == Config.FLK();
        SwapParams memory params = SwapParams({
            zeroForOne: flkIsToken0,
            amountSpecified: -int256(amount),
            sqrtPriceLimitX96: MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user, key, params, BalanceDelta.wrap(0), abi.encodePacked(user));
    }

    function _executeSellSwap(address user, PoolKey memory key, uint256 amount) internal {
        bool flkIsToken0 = Currency.unwrap(key.currency0) == Config.FLK();
        SwapParams memory params = SwapParams({
            zeroForOne: !flkIsToken0,
            amountSpecified: -int256(amount),
            sqrtPriceLimitX96: flkIsToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT
        });

        vm.prank(address(mockPoolManager));
        hook.afterSwap(user, key, params, BalanceDelta.wrap(0), abi.encodePacked(user));
    }
}

/**
 * @notice Mock pool manager that allows hook calls from tests
 */
contract MockPoolManager {
    function unlock(bytes calldata) external returns (bytes memory) {
        return "";
    }

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

