// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { StakingRewards } from "../src/staking/StakingRewards.sol";

contract DeployStaking is Script {
    struct TokenAddresses {
        address rewards;
        address staking;
    }

    address constant FOUNDATION_MULTISIG = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    // TODO: replace with backend wallet which will top up pools
    address constant REWARDS_DISTRIBUTOR = 0x75A6085Bbc25665B6891EA94475E6120897BA90b;

    function setUp() public { }

    function run() public {
        bytes32 salt = keccak256(abi.encodePacked("FLK_STAKING", "v1.0"));

        TokenAddresses memory tokens = TokenAddresses({
            rewards: 0x170B89C690Ec367A0C200Aaaf96c14B3DCF23f7F,
            staking: 0x170B89C690Ec367A0C200Aaaf96c14B3DCF23f7F
        });

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
                        21 days
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
                        365 days
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
