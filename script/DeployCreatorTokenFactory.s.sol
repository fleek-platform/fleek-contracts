// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CharacterTokenFactory } from "../src/creator-tokens/CreatorTokenFactory.sol";
import { BondingCurveFactory } from "../src/creator-tokens/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../src/creator-tokens/CreatorCoinFactory.sol";
import { FactoryConfig } from "../src/creator-tokens/lib/FactoryConfig.sol";

contract DeployCreatorTokenFactory is Script {
    function run() public {
        vm.startBroadcast();

        // 1. Deploy sub-factories (deployer is initial owner)
        BondingCurveFactory bondingCurveFactory = new BondingCurveFactory(msg.sender);
        console.log("BondingCurveFactory deployed at:", address(bondingCurveFactory));

        CreatorCoinFactory creatorCoinFactory = new CreatorCoinFactory(msg.sender);
        console.log("CreatorCoinFactory deployed at:", address(creatorCoinFactory));

        // 2. Deploy main factory
        CharacterTokenFactory characterTokenFactory = new CharacterTokenFactory(
            FactoryConfig.FOUNDATION, address(bondingCurveFactory), address(creatorCoinFactory)
        );
        console.log("CharacterTokenFactory deployed at:", address(characterTokenFactory));

        // 3. Transfer ownership of sub-factories to main factory
        bondingCurveFactory.transferOwnership(address(characterTokenFactory));
        console.log("BondingCurveFactory ownership transferred to CharacterTokenFactory");

        creatorCoinFactory.transferOwnership(address(characterTokenFactory));
        console.log("CreatorCoinFactory ownership transferred to CharacterTokenFactory");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("CharacterTokenFactory:", address(characterTokenFactory));
        console.log("BondingCurveFactory:", address(bondingCurveFactory));
        console.log("CreatorCoinFactory:", address(creatorCoinFactory));
    }
}
