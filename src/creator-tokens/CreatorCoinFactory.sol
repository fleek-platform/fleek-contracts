// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";

contract CreatorCoinFactory is Ownable {
    constructor(address _owner) Ownable(_owner) { }

    error TokenTransferFailed();

    function deploy(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) external onlyOwner returns (CreatorCoin, CreatorVesting) {
        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol, FactoryConfig.CREATOR_COIN_SUPPLY);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        require(
            creatorCoin.transfer(FactoryConfig.FOUNDATION, FactoryConfig.CREATOR_FUND_ALLOCATION),
            TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(address(creatorVesting), FactoryConfig.CREATOR_ALLOCATION),
            TokenTransferFailed()
        );
        require(
            creatorCoin.transfer(
                FactoryConfig.FAN_POOL_CONTROLLER, FactoryConfig.FAN_POOL_ALLOCATION
            ),
            TokenTransferFailed()
        );

        return (creatorCoin, creatorVesting);
    }

    function transferToBondingCurve(address _creatorCoin, address _bondingCurve)
        external
        onlyOwner
    {
        require(
            CreatorCoin(_creatorCoin)
                .transfer(_bondingCurve, FactoryConfig.BONDING_CURVE_ALLOCATION),
            TokenTransferFailed()
        );
    }
}
