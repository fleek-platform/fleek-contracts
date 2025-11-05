// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { UniversalAntiFlipFeeHook } from "../src/creator-tokens/hooks/UniversalAntiFlipFeeHook.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Config } from "../src/creator-tokens/libraries/Config.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolSwapTest } from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { SwapParams } from "@uniswap/v4-core/src/types/PoolOperation.sol";
import { BaseUniswapDeployments } from "../src/creator-tokens/libraries/BaseUniswapDeployments.sol";

contract TestPerTokenTracking is Script {
    address constant FACTORY = 0x015b8c471fF80Bd72f759Bf3C6452335E1c24De5;
    address constant HOOK = 0xc7Dfca1B66f1475029ed1812B38139e1bF5c8044;

    function deployToken(string memory name, string memory symbol) public {
        vm.startBroadcast();

        CreatorTokenFactory factory = CreatorTokenFactory(FACTORY);

        console.log("=== Deploying New Creator Token ===");
        console.log("Name:", name);
        console.log("Symbol:", symbol);

        uint64 vestingStart = uint64(block.timestamp);

        vm.recordLogs();
        factory.deployNew(msg.sender, name, symbol, vestingStart);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        address token;
        address bondingCurve;
        address vestingWallet;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (token, bondingCurve, vestingWallet) =
                    abi.decode(logs[i].data, (address, address, address));
                break;
            }
        }

        console.log("\n=== Deployment Complete ===");
        console.log("Token:", token);
        console.log("BondingCurve:", bondingCurve);
        console.log("VestingWallet:", vestingWallet);
        console.log("\nNext steps:");
        console.log(
            "1. Approve FLK: forge script script/TestPerTokenTracking.s.sol --sig \"approveFLK(address,uint256)\"",
            bondingCurve,
            "1000000000000000000000 --rpc-url $RPC --broadcast"
        );
        console.log(
            "2. Buy tokens: forge script script/TestPerTokenTracking.s.sol --sig \"buyTokens(address,uint256,uint256)\"",
            bondingCurve,
            "1000000000000000000 0 --rpc-url $RPC --broadcast"
        );

        vm.stopBroadcast();
    }

    function approveFLK(address bondingCurve, uint256 amount) public {
        vm.startBroadcast();

        address flk = Config.FLK();

        console.log("=== Approving FLK ===");
        console.log("FLK Token:", flk);
        console.log("Spender (BondingCurve):", bondingCurve);
        console.log("Amount:", amount);

        IERC20(flk).approve(bondingCurve, amount);

        console.log("\n=== Approval Complete ===");
        console.log("You can now buy tokens!");

        vm.stopBroadcast();
    }

    function buyTokens(address bondingCurve, uint256 flkAmount, uint256 minTokensOut) public {
        vm.startBroadcast();

        BondingCurve curve = BondingCurve(bondingCurve);
        (, address token,,,,,) = curve.metadata();

        console.log("=== Buying Tokens ===");
        console.log("BondingCurve:", bondingCurve);
        console.log("Token:", token);
        console.log("FLK Amount:", flkAmount);
        console.log("Min Tokens Out:", minTokensOut);

        curve.buy(flkAmount, minTokensOut);

        console.log("\n=== Buy Complete ===");

        vm.stopBroadcast();
    }

    function checkBuyTimestamp(address token, address user) public view {
        UniversalAntiFlipFeeHook hook = UniversalAntiFlipFeeHook(HOOK);

        console.log("=== Checking Buy Timestamp ===");
        console.log("Token:", token);
        console.log("User:", user);
        console.log("Hook:", HOOK);

        uint256 lastBuyTime = hook.userLastBuy(token, user);

        console.log("\n=== Results ===");
        console.log("Last Buy Time:", lastBuyTime);
        console.log("Current Time:", block.timestamp);

        if (lastBuyTime > 0) {
            uint256 elapsed = block.timestamp - lastBuyTime;
            console.log("Time Since Buy:", elapsed, "seconds");

            if (elapsed < 120) {
                console.log("Status: WITHIN ANTI-FLIP WINDOW (30-120s)");
                console.log("Selling now would trigger 12% fee");
            } else {
                console.log("Status: OUTSIDE ANTI-FLIP WINDOW");
                console.log("Selling now would trigger only 2% fee");
            }
        } else {
            console.log("Status: NO BUY RECORDED");
        }
    }

    function checkMultipleTokens(address[] memory tokens, address user) public view {
        UniversalAntiFlipFeeHook hook = UniversalAntiFlipFeeHook(HOOK);

        console.log("=== Checking Multiple Tokens ===");
        console.log("User:", user);
        console.log("Number of tokens:", tokens.length);
        console.log("Current Time:", block.timestamp);
        console.log("");

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 lastBuyTime = hook.userLastBuy(token, user);

            console.log("Token", i + 1, ":", token);
            console.log("  Last Buy Time:", lastBuyTime);

            if (lastBuyTime > 0) {
                uint256 elapsed = block.timestamp - lastBuyTime;
                console.log("  Time Since Buy:", elapsed, "seconds");
                console.log("  Anti-Flip Fee:", elapsed < 120 ? "12%" : "2%");
            } else {
                console.log("  Status: No buy recorded");
            }
            console.log("");
        }
    }

    function getBondingCurveInfo(address bondingCurve) public view {
        BondingCurve curve = BondingCurve(bondingCurve);

        console.log("=== Bonding Curve Info ===");
        console.log("Address:", bondingCurve);

        (
            address creator,
            address creatorToken,
            ,
            address vestingWallet,
            address universalHook,
            uint256 deploymentTimestamp,
            bool graduated
        ) = curve.metadata();

        console.log("\nMetadata:");
        console.log("  Creator:", creator);
        console.log("  Token:", creatorToken);
        console.log("  Vesting Wallet:", vestingWallet);
        console.log("  Universal Hook:", universalHook);
        console.log("  Graduated:", graduated);
        console.log("  Deployment Time:", deploymentTimestamp);

        console.log("\nTokens Sold:", curve.creatorTokensSold());

        // Log token balance in bonding curve
        uint256 tokenBalance = IERC20(creatorToken).balanceOf(bondingCurve);
        uint256 flkBalance = IERC20(Config.FLK()).balanceOf(bondingCurve);

        console.log("\nBalances:");
        console.log("  FLK Balance:", flkBalance);
        console.log("  Token Balance:", tokenBalance);
    }

    function runFullFlow() public {
        vm.startBroadcast();

        console.log("=== FULL PER-TOKEN TRACKING TEST ===\n");

        CreatorTokenFactory factory = CreatorTokenFactory(FACTORY);
        address flk = Config.FLK();

        console.log("Step 1: Deploy Token 1");
        uint64 vestingStart = uint64(block.timestamp);

        vm.recordLogs();
        factory.deployNew(msg.sender, "TestToken1", "TT1", vestingStart);
        Vm.Log[] memory logs1 = vm.getRecordedLogs();

        address token1;
        address curve1;
        for (uint256 i = 0; i < logs1.length; i++) {
            if (logs1[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (token1, curve1,) = abi.decode(logs1[i].data, (address, address, address));
                break;
            }
        }
        console.log("  Token1:", token1);
        console.log("  Curve1:", curve1);

        console.log("\nStep 2: Deploy Token 2");
        vm.recordLogs();
        factory.deployNew(msg.sender, "TestToken2", "TT2", vestingStart);
        Vm.Log[] memory logs2 = vm.getRecordedLogs();

        address token2;
        address curve2;
        for (uint256 i = 0; i < logs2.length; i++) {
            if (logs2[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (token2, curve2,) = abi.decode(logs2[i].data, (address, address, address));
                break;
            }
        }
        console.log("  Token2:", token2);
        console.log("  Curve2:", curve2);

        console.log("\nStep 3: Approve FLK for both curves");
        IERC20(flk).approve(curve1, type(uint256).max);
        IERC20(flk).approve(curve2, type(uint256).max);
        console.log("  Approved!");

        console.log("\nStep 4: Buy from Token 1");
        BondingCurve(curve1).buy(1e18, 0);
        console.log("  Token1 bought");

        console.log("\nStep 5: Buy from Token 2 (same block)");
        BondingCurve(curve2).buy(1e18, 0);
        console.log("  Token2 bought");

        console.log("\n=== SUCCESS ===");
        console.log("Both tokens purchased from bonding curve");
        console.log("Use checkBuyTimestamp to verify per-token tracking after graduation");

        vm.stopBroadcast();
    }

    function graduateCurve(address bondingCurve) public {
        vm.startBroadcast();

        BondingCurve curve = BondingCurve(bondingCurve);
        (, address token,,,,, bool graduated) = curve.metadata();

        console.log("=== Graduating Bonding Curve ===");
        console.log("BondingCurve:", bondingCurve);
        console.log("Token:", token);
        console.log("Already graduated:", graduated);

        if (graduated) {
            console.log("\n[INFO] Already graduated!");
            vm.stopBroadcast();
            return;
        }

        uint256 tokensSold = curve.creatorTokensSold();
        uint256 graduationThreshold = Config.BONDING_CURVE_ALLOCATION / 2;
        uint256 remaining = graduationThreshold - tokensSold;

        console.log("\nTokens sold:", tokensSold);
        console.log("Graduation threshold:", graduationThreshold);
        console.log("Tokens remaining to graduate:", remaining);

        if (remaining == 0) {
            console.log("\n[INFO] Threshold reached, call buy to trigger graduation");
        } else {
            console.log("\n[INFO] Need to buy", remaining, "more tokens to graduate");
            console.log("Approximate FLK needed: TBD (depends on curve)");
        }

        vm.stopBroadcast();
    }

    function buyToGraduate(address bondingCurve, uint256 maxFLK) public {
        vm.startBroadcast();

        BondingCurve curve = BondingCurve(bondingCurve);

        console.log("=== Buying to Graduate ===");
        console.log("BondingCurve:", bondingCurve);
        console.log("Max FLK to spend:", maxFLK);

        IERC20(Config.FLK()).approve(bondingCurve, maxFLK);

        curve.buy(maxFLK, 0);

        (,,,,,, bool graduated) = curve.metadata();

        if (graduated) {
            console.log("\n[SUCCESS] Bonding curve graduated!");
            console.log("Token is now on Uniswap V4 with the UniversalAntiFlipFeeHook");
        } else {
            console.log("\n[INFO] Not yet graduated. Buy more tokens.");
        }

        vm.stopBroadcast();
    }

    function swapOnGraduatedPool(address token, uint256 flkAmount, bool isBuy) public {
        vm.startBroadcast();

        address flk = Config.FLK();

        console.log("=== Swapping on Graduated Pool ===");
        console.log("Token:", token);
        console.log("FLK Amount:", flkAmount);
        console.log("Direction:", isBuy ? "BUY" : "SELL");

        address token0 = flk < token ? flk : token;
        address token1 = flk < token ? token : flk;
        bool flkIsToken0 = token0 == flk;

        PoolSwapTest swapRouter =
            new PoolSwapTest(IPoolManager(BaseUniswapDeployments.POOL_MANAGER()));

        IERC20(isBuy ? flk : token).approve(address(swapRouter), type(uint256).max);

        swapRouter.swap(
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: 0,
                tickSpacing: 200,
                hooks: IHooks(HOOK)
            }),
            SwapParams({
                zeroForOne: isBuy ? flkIsToken0 : !flkIsToken0,
                // casting to 'int256' is safe because flkAmount is controlled and well below int256.max
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(flkAmount),
                sqrtPriceLimitX96: (isBuy ? flkIsToken0 : !flkIsToken0)
                    ? 4295128740
                    : 1461446703485210103287273052203988822378723970341
            }),
            PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }),
            ""
        );

        console.log("\n=== Swap Complete ===");

        vm.stopBroadcast();
    }

    function runGraduationFlow() public {
        vm.startBroadcast();

        console.log("=== FULL GRADUATION & HOOK TEST ===\n");

        CreatorTokenFactory factory = CreatorTokenFactory(FACTORY);
        UniversalAntiFlipFeeHook hook = UniversalAntiFlipFeeHook(HOOK);
        address flk = Config.FLK();

        console.log("Step 1: Deploy Test Token");
        uint64 vestingStart = uint64(block.timestamp);

        vm.recordLogs();
        factory.deployNew(msg.sender, "GradTest", "GRAD", vestingStart);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address token;
        address curve;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (token, curve,) = abi.decode(logs[i].data, (address, address, address));
                break;
            }
        }
        console.log("  Token:", token);
        console.log("  Curve:", curve);

        console.log("\nStep 2: Check graduation requirements");
        uint256 graduationThreshold = Config.BONDING_CURVE_ALLOCATION / 2;
        console.log("  Need to sell:", graduationThreshold, "tokens");

        console.log("\nStep 3: Approve FLK");
        IERC20(flk).approve(curve, type(uint256).max);
        console.log("  Approved!");

        console.log("\nStep 4: Buy tokens to trigger graduation");
        console.log("  [NOTE] This requires significant FLK (~20k FLK)");
        console.log("  [NOTE] Use buyToGraduate() with exact amount instead");

        console.log("\nStep 5: Check hook registration after graduation");
        address creator = hook.tokenToCreator(token);
        if (creator != address(0)) {
            console.log("  [SUCCESS] Token registered with hook!");
            console.log("  Creator:", creator);

            uint256 lastBuy = hook.userLastBuy(token, msg.sender);
            console.log("  User last buy:", lastBuy);
        } else {
            console.log("  [INFO] Not yet graduated or registered");
        }

        console.log("\n[INFO] Use graduateCurve() and swapOnGraduatedPool() for full test");

        vm.stopBroadcast();
    }
}
