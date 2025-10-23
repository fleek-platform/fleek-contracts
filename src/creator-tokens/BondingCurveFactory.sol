// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BondingCurve } from "./BondingCurve.sol";
import { FactoryConfig } from "./lib/FactoryConfig.sol";

contract BondingCurveFactory is Ownable {
    constructor(address _owner) Ownable(_owner) { }

    function deploy(address _creator, address _creatorToken, address _vestingWallet)
        external
        onlyOwner
        returns (BondingCurve)
    {
        BondingCurve bondingCurve = new BondingCurve(
            _creator,
            _creatorToken,
            FactoryConfig.GRADUATION_THRESHOLD,
            FactoryConfig.BASE_PRICE,
            FactoryConfig.BONDING_CURVE_ALLOCATION / 2,
            _vestingWallet
        );

        return bondingCurve;
    }
}
