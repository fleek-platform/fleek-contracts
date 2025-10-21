// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { CharacterTokenFactory } from "../src/creator-tokens/CreatorTokenFactory.sol";

contract DeployFactoryAndToken is Script {
    function run() external {
        address creator = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885; // Creator address
        string memory name = "Test Token";
        string memory symbol = "TEST";

        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.startBroadcast();

        CharacterTokenFactory factory = new CharacterTokenFactory();
        console.log("Factory deployed at:", address(factory));

        factory.deployNew(creator, name, symbol, vestingStart, vestingDuration, cliffDuration);

        console.log("Token deployed for creator:", creator);

        vm.stopBroadcast();
    }
}
