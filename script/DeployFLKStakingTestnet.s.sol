// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { StakingRewards } from "../src/staking/StakingRewards.sol";

contract DeployStaking is Script {
    struct TokenAddresses {
        address rewards;
        address staking;
    }

    address constant FOUNDATION_MULTISIG = 0x75A6085Bbc25665B6891EA94475E6120897BA90b;
    address constant REWARDS_DISTRIBUTOR = 0x75A6085Bbc25665B6891EA94475E6120897BA90b;

    function setUp() public { }

    function run() public {
        bytes32 salt = keccak256(abi.encodePacked("FLK_STAKING", "v1.0"));

        TokenAddresses memory tokens = TokenAddresses({ rewards: address(0), staking: address(0) });

        address basePoolAddr = vm.computeCreate2Address(
            salt,
            keccak256(
                abi.encodePacked(
                    type(StakingRewards).creationCode,
                    abi.encode(
                        FOUNDATION_MULTISIG,
                        tokens.rewards,
                        tokens.staking,
                        REWARDS_DISTRIBUTOR,
                        1 minutes
                    )
                )
            )
        );

        address boostedPoolAddr = vm.computeCreate2Address(
            salt,
            keccak256(
                abi.encodePacked(
                    type(StakingRewards).creationCode,
                    abi.encode(
                        FOUNDATION_MULTISIG,
                        tokens.rewards,
                        tokens.staking,
                        REWARDS_DISTRIBUTOR,
                        10 minutes
                    )
                )
            )
        );

        console.log("Predicted address base pool:", basePoolAddr);
        console.log("Predicted address boosted pool:", boostedPoolAddr);

        vm.startBroadcast();

        StakingRewards baseStakingRewards = new StakingRewards{ salt: salt }(
            FOUNDATION_MULTISIG, tokens.rewards, tokens.staking, REWARDS_DISTRIBUTOR, 21 days
        );

        StakingRewards boostedStakingRewards = new StakingRewards{ salt: salt }(
            FOUNDATION_MULTISIG, tokens.rewards, tokens.staking, REWARDS_DISTRIBUTOR, 365 days
        );

        vm.stopBroadcast();

        require(address(baseStakingRewards) == basePoolAddr, "Base pool address mismatch");
        require(address(boostedStakingRewards) == boostedPoolAddr, "Boosted pool address mismatch");
    }
}
