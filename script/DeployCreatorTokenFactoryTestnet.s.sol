// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CreatorTokenFactory } from "../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurve } from "../src/creator-tokens/curve/BondingCurve.sol";
import { BondingCurveFactory } from "../src/creator-tokens/core/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/core/CreatorCoinFactory.sol";

/**
 * @title DeployCreatorTokenFactoryTestnet
 * @notice Deploys the CreatorTokenFactory system on Base Sepolia testnet
 * 
 * Testnet Configuration:
 * - Foundation: 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885
 * - Fan Pool Controller: 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885
 * - FLK Token: 0x88DB73F86c7025608420f447ae003b7CD3286E71
 * - PoolManager: 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408
 * 
 * Usage:
 *   forge script script/DeployCreatorTokenFactoryTestnet.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeployCreatorTokenFactoryTestnet is Script {
    // Testnet Configuration (Base Sepolia)
    address constant TESTNET_FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address constant TESTNET_FAN_POOL_CONTROLLER = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address constant TESTNET_FLK = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    
    // Uniswap V4 addresses (Base Sepolia)
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;

    function run() public {
        console.log("=== Deploying CreatorTokenFactory to Base Sepolia ===");
        console.log("Deployer:", msg.sender);
        console.log("");
        console.log("Testnet Configuration:");
        console.log("  Foundation:", TESTNET_FOUNDATION);
        console.log("  Fan Pool Controller:", TESTNET_FAN_POOL_CONTROLLER);
        console.log("  FLK Token:", TESTNET_FLK);
        console.log("");
        console.log("Uniswap V4 Addresses:");
        console.log("  PoolManager:", POOL_MANAGER);
        console.log("  PositionManager:", POSITION_MANAGER);
        console.log("  UniversalRouter:", UNIVERSAL_ROUTER);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy BondingCurve implementation (used by clones)
        BondingCurve bondingCurveImpl = new BondingCurve();
        console.log("BondingCurve implementation deployed at:", address(bondingCurveImpl));

        // 2. Deploy sub-factories (deployer is initial owner)
        BondingCurveFactory bondingCurveFactory = new BondingCurveFactory(
            msg.sender,
            address(bondingCurveImpl)
        );
        console.log("BondingCurveFactory deployed at:", address(bondingCurveFactory));

        CreatorCoinFactory creatorCoinFactory = new CreatorCoinFactory(msg.sender);
        console.log("CreatorCoinFactory deployed at:", address(creatorCoinFactory));

        // 3. Deploy main factory (foundation gets ownership)
        CreatorTokenFactory creatorTokenFactory = new CreatorTokenFactory(
            TESTNET_FOUNDATION,
            address(bondingCurveFactory),
            address(creatorCoinFactory)
        );
        console.log("CreatorTokenFactory deployed at:", address(creatorTokenFactory));

        // 4. Transfer ownership of sub-factories to main factory
        bondingCurveFactory.transferOwnership(address(creatorTokenFactory));
        console.log("BondingCurveFactory ownership transferred to CreatorTokenFactory");

        creatorCoinFactory.transferOwnership(address(creatorTokenFactory));
        console.log("CreatorCoinFactory ownership transferred to CreatorTokenFactory");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("Deployed Contracts:");
        console.log("  BondingCurve Implementation:", address(bondingCurveImpl));
        console.log("  CreatorTokenFactory:", address(creatorTokenFactory));
        console.log("  BondingCurveFactory:", address(bondingCurveFactory));
        console.log("  CreatorCoinFactory:", address(creatorCoinFactory));
        console.log("");
        console.log("Ownership:");
        console.log("  CreatorTokenFactory owner:", TESTNET_FOUNDATION);
        console.log("  BondingCurveFactory owner:", address(creatorTokenFactory));
        console.log("  CreatorCoinFactory owner:", address(creatorTokenFactory));
        console.log("");
        
        _printNextSteps(address(creatorTokenFactory));
    }

    function _printNextSteps(address factory) internal view {
        console.log("=== Next Steps ===");
        console.log("");
        console.log("1. VERIFY CONTRACTS (if --verify wasn't used)");
        console.log("   forge verify-contract <ADDRESS> <CONTRACT_PATH> --chain base-sepolia");
        console.log("");
        console.log("2. CREATE A TEST CREATOR TOKEN");
        console.log("   The foundation owner can now deploy creator tokens:");
        console.log("");
        console.log("   cast send", factory, "\\");
        console.log("     \"deployNew(address,string,string,uint64,uint64,uint64)\" \\");
        console.log("     <CREATOR_ADDRESS> \\");
        console.log("     \"Test Creator Token\" \\");
        console.log("     \"TCT\" \\");
        console.log("     $(cast block latest timestamp) \\");
        console.log("     $((365 * 24 * 60 * 60)) \\");  // 1 year vesting
        console.log("     $((30 * 24 * 60 * 60)) \\");    // 30 day cliff
        console.log("     --rpc-url $BASE_SEPOLIA_RPC \\");
        console.log("     --private-key $PRIVATE_KEY");
        console.log("");
        console.log("3. GET FLK TOKENS FOR TESTING");
        console.log("   You'll need testnet FLK to buy creator tokens:");
        console.log("   FLK Address:", TESTNET_FLK);
        console.log("");
        console.log("4. FIND YOUR BONDING CURVE");
        console.log("   After creating a token, get the bonding curve address:");
        console.log("");
        console.log("   cast logs \\");
        console.log("     --address", factory, "\\");
        console.log("     --from-block latest \\");
        console.log("     --rpc-url $BASE_SEPOLIA_RPC");
        console.log("");
        console.log("5. BUY ON THE BONDING CURVE");
        console.log("   # Approve FLK");
        console.log("   cast send", TESTNET_FLK, "\\");
        console.log("     \"approve(address,uint256)\" \\");
        console.log("     <BONDING_CURVE_ADDRESS> \\");
        console.log("     $(cast max-uint256) \\");
        console.log("     --rpc-url $BASE_SEPOLIA_RPC");
        console.log("");
        console.log("   # Buy tokens (2% fee applied)");
        console.log("   cast send <BONDING_CURVE_ADDRESS> \\");
        console.log("     \"buy(uint256,uint256)\" \\");
        console.log("     1000000000000000000000 \\");  // 1000 FLK
        console.log("     0 \\");                        // minOut
        console.log("     --rpc-url $BASE_SEPOLIA_RPC");
        console.log("");
        console.log("6. REACH GRADUATION (20,675 FLK)");
        console.log("   Keep buying until the bonding curve graduates.");
        console.log("   At graduation, it will:");
        console.log("   - Deploy the AntiFlipFeeHook");
        console.log("   - Create a Uniswap V4 pool at:", POOL_MANAGER);
        console.log("   - Add all remaining liquidity");
        console.log("   - Burn the LP NFT (lock liquidity forever)");
        console.log("");
        console.log("7. TEST THE HOOK");
        console.log("   After graduation, test swaps via UniversalRouter:", UNIVERSAL_ROUTER);
        console.log("");
        console.log("   Test A: Buy (2% fee)");
        console.log("   Test B: Quick flip (12% fee - sell within 30-120s)");
        console.log("   Test C: Normal sell (2% fee - sell after window)");
        console.log("");
        console.log("8. VERIFY FEE COLLECTION");
        console.log("   Check balances to confirm fees:");
        console.log("");
        console.log("   cast call", TESTNET_FLK, "\"balanceOf(address)\"", TESTNET_FOUNDATION);
        console.log("   cast call", TESTNET_FLK, "\"balanceOf(address)\" <CREATOR_ADDRESS>");
        console.log("");
        console.log("=== Testnet Addresses for Reference ===");
        console.log("Foundation:", TESTNET_FOUNDATION);
        console.log("FLK Token:", TESTNET_FLK);
        console.log("PoolManager:", POOL_MANAGER);
        console.log("UniversalRouter:", UNIVERSAL_ROUTER);
        console.log("");
        console.log("Happy testing!");
        console.log("");
    }
}
