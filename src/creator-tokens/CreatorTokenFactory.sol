// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { FactoryConfig } from "./FactoryConfig.sol";

contract CharacterTokenFactory is Ownable2Step {
    FactoryConfig public immutable config;

    constructor(address _foundation, address _config) Ownable(_foundation) {
        config = FactoryConfig(_config);
    }

    mapping(string => bool) public tokenNames;

    event TokenDeployed(address newToken, address bondingCurve);

    error TokenNameExists();
    error TokenTransferFailed();

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

        // Load config into memory
        (uint256 bcAlloc, uint256 creatorAlloc, uint256 fundAlloc, uint256 fanAlloc) =
            config.allocations();
        (uint256 threshold, uint256 basePrice) = config.bondingCurveCriteria();
        (address foundation, address fanPoolController) = config.wallets();
        uint256 supply = config.creatorCoinSupply();

        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol, supply);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        BondingCurve bondingCurve = new BondingCurve(
            _creator, config.FLK(), address(creatorCoin), threshold, basePrice, bcAlloc / 2
        );

        require(creatorCoin.transfer(foundation, fundAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(address(bondingCurve), bcAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(address(creatorVesting), creatorAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(fanPoolController, fanAlloc), TokenTransferFailed());

        emit TokenDeployed({ newToken: address(creatorCoin), bondingCurve: address(bondingCurve) });
    }
}
