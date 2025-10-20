// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CreatorToken } from "./CreatorToken.sol";
import { CreatorVesting } from "./CreatorVesting.sol";

contract CharacterTokenFactory {
    address FOUNDATION_MULTISIG = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    uint256 constant GRADUATION_THRESHOLD = 20_000e18; // 20,000  parent tokens
    uint256 constant BASE_PRICE = 8e13; //  calibrated base price
    uint256 constant CHARACTER_SUPPLY = 475_000_000e18; // 475M tokens split bonding/LP

    address public creator;

    // check that token name doesnt already exist
    mapping(string => bool) public tokenNames;

    function deployNew(
        address _creator,
        string memory _name,
        string memory _symbol,
        uint64 _vestingStart,
        uint64 _vestingDuration,
        uint64 _cliffDuration
    ) public {
        CreatorToken creatorToken = new CreatorToken(_name, _symbol);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);
    }
}
