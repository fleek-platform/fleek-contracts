// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { BondingCurve } from "./BondingCurve.sol";
import { FactoryConfig } from "./FactoryConfig.sol";

contract BondingCurveFactory {
    FactoryConfig public immutable config;

    constructor(address _config) {
        config = FactoryConfig(_config);
    }

    function deploy(address _creator, address _creatorToken) external returns (BondingCurve) {
        (uint256 bcAlloc,,,) = config.allocations();
        (uint256 threshold, uint256 basePrice) = config.bondingCurveCriteria();

        BondingCurve bondingCurve = new BondingCurve(
            _creator, config.FLK(), _creatorToken, threshold, basePrice, bcAlloc / 2
        );

        return bondingCurve;
    }
}
