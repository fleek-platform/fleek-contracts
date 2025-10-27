// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {BaseUniswapDeployments} from "../../../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

/**
 * @title Deployers
 * @notice Base deployer contract for testing hooks on Base mainnet fork
 * @dev Uses existing Uniswap V4 deployments on Base mainnet
 */
contract Deployers is Test {
    using PoolIdLibrary for PoolKey;

    // Uniswap V4 contracts on Base mainnet
    IPoolManager public poolManager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiquidityRouter;

    // Test constants
    bytes internal constant ZERO_BYTES = new bytes(0);
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 internal constant MIN_PRICE_LIMIT = 4295128740;
    uint160 internal constant MAX_PRICE_LIMIT = 1461446703485210103287273052203988822378723970341;

    /**
     * @notice Deploy test routers using Base mainnet's PoolManager
     * @dev Call this in setUp() after forking Base mainnet
     */
    function deployRouters() internal {
        poolManager = IPoolManager(BaseUniswapDeployments.POOL_MANAGER);
        
        // Deploy test routers that interact with the real PoolManager
        swapRouter = new PoolSwapTest(poolManager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);

        vm.label(address(poolManager), "PoolManager");
        vm.label(address(swapRouter), "SwapRouter");
        vm.label(address(modifyLiquidityRouter), "ModifyLiquidityRouter");
    }

    /**
     * @notice Deploy a mock ERC20 token with approvals
     */
    function deployToken(string memory name, string memory symbol) internal returns (MockERC20 token) {
        token = new MockERC20(name, symbol, 18);
        token.mint(address(this), 10_000_000 ether);

        // Approve routers
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
    }

    /**
     * @notice Deploy and sort two currencies for a pool
     */
    function deployCurrencyPair() internal returns (Currency currency0, Currency currency1) {
        MockERC20 token0 = deployToken("Token0", "TK0");
        MockERC20 token1 = deployToken("Token1", "TK1");

        // Sort tokens by address
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        vm.label(address(token0), "Currency0");
        vm.label(address(token1), "Currency1");
    }

    /**
     * @notice Initialize a pool with a hook
     */
    function initPool(
        Currency currency0,
        Currency currency1,
        IHooks hook,
        uint24 fee,
        uint160 sqrtPriceX96
    ) internal returns (PoolKey memory key, PoolId id) {
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: fee,
            tickSpacing: 60,
            hooks: hook
        });
        id = key.toId();
        
        poolManager.initialize(key, sqrtPriceX96);
    }

    /**
     * @notice Add liquidity to a pool
     */
    function addLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta
    ) internal returns (BalanceDelta delta) {
        delta = modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: 0
            }),
            ZERO_BYTES
        );
    }

    /**
     * @notice Execute a swap
     */
    function executeSwap(
        PoolKey memory key,
        bool zeroForOne,
        int256 amountSpecified
    ) internal returns (BalanceDelta delta) {
        delta = swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            }),
            PoolSwapTest.TestSettings({
                takeClaims: false,
                settleUsingBurn: false
            }),
            ZERO_BYTES
        );
    }
}
