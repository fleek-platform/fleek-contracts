// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { BondingCurveFactory } from "./BondingCurveFactory.sol";
import { CreatorCoinFactory } from "./CreatorCoinFactory.sol";
import { FactoryConfig } from "./FactoryConfig.sol";

contract CharacterTokenFactory is Ownable2Step {
    FactoryConfig public immutable config;
    BondingCurveFactory public immutable bondingCurveFactory;
    CreatorCoinFactory public immutable creatorCoinFactory;

    constructor(
        address _foundation,
        address _config,
        address _bondingCurveFactory,
        address _creatorCoinFactory
    ) Ownable(_foundation) {
        config = FactoryConfig(_config);
        bondingCurveFactory = BondingCurveFactory(_bondingCurveFactory);
        creatorCoinFactory = CreatorCoinFactory(_creatorCoinFactory);
    }

    mapping(string => bool) public tokenNames;

    event TokenDeployed(address newToken, address bondingCurve, address vestingContract);

    error TokenNameExists();

    function deployNew(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) public {
        require(!tokenNames[_name], TokenNameExists());
        tokenNames[_name] = true;

        BondingCurve bondingCurve = bondingCurveFactory.deploy(_creator, address(0));

        (CreatorCoin creatorCoin, CreatorVesting creatorVesting) = creatorCoinFactory.deploy(
            _creator,
            _name,
            _symbol,
            _vestingStart,
            _vestingDuration,
            _cliffDuration,
            address(bondingCurve)
        );

        emit TokenDeployed({
            newToken: address(creatorCoin),
            bondingCurve: address(bondingCurve),
            vestingContract: address(creatorVesting)
        });
    }
}
