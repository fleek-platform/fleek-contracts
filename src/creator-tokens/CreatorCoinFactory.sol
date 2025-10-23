// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { FactoryConfig } from "./FactoryConfig.sol";

contract CreatorCoinFactory {
    FactoryConfig public immutable config;

    constructor(address _config) {
        config = FactoryConfig(_config);
    }

    error TokenTransferFailed();

    function deploy(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration,
        address _bondingCurve
    ) external returns (CreatorCoin, CreatorVesting) {
        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol, config.creatorCoinSupply());

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        (uint256 bcAlloc, uint256 creatorAlloc, uint256 fundAlloc, uint256 fanAlloc) =
            config.allocations();
        (address foundation, address fanPoolController) = config.wallets();

        require(creatorCoin.transfer(foundation, fundAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(_bondingCurve, bcAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(address(creatorVesting), creatorAlloc), TokenTransferFailed());
        require(creatorCoin.transfer(fanPoolController, fanAlloc), TokenTransferFailed());

        return (creatorCoin, creatorVesting);
    }
}
