// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { CreatorCoin } from "./CreatorCoin.sol";
import { CreatorVesting } from "./CreatorVesting.sol";
import { BondingCurve } from "./BondingCurve.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract CharacterTokenFactory is AccessControlDefaultAdminRules {
    address FOUNDATION_MULTISIG = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    address constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;
    uint256 constant GRADUATION_THRESHOLD = 20_000e18; // 20,000 FLK
    uint256 constant BASE_PRICE = 8e13; //  calibrated base price
    uint256 constant CHARACTER_SUPPLY = 450_000_000e18;

    constructor() AccessControlDefaultAdminRules(3 days, FOUNDATION_MULTISIG) { }

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
        CreatorCoin creatorCoin = new CreatorCoin(_name, _symbol);

        CreatorVesting creatorVesting =
            new CreatorVesting(_creator, _vestingStart, _vestingDuration, _cliffDuration);

        BondingCurve bondingCurve = new BondingCurve(
            _creator,
            FLK,
            address(creatorCoin),
            GRADUATION_THRESHOLD,
            BASE_PRICE,
            CHARACTER_SUPPLY / 2
        );

        creatorCoin.transfer(FOUNDATION_MULTISIG, 50_000_000e18);
        creatorCoin.transfer(address(bondingCurve), CHARACTER_SUPPLY);
        creatorCoin.transfer(address(creatorVesting), 250_000_000e18);
    }
}
