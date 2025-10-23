// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

library FactoryConfig {
    uint256 internal constant BONDING_CURVE_ALLOCATION = 450_000e18;
    uint256 internal constant CREATOR_ALLOCATION = 250_000e18;
    uint256 internal constant CREATOR_FUND_ALLOCATION = 50_000e18;
    uint256 internal constant FAN_POOL_ALLOCATION = 250_000e18;

    uint256 internal constant GRADUATION_THRESHOLD = 20_675e18;
    uint256 internal constant BASE_PRICE = 1e15;

    address internal constant FOUNDATION = 0x5719061AD5052C1f2E4c942c68F35935adD31f7E;
    address internal constant FAN_POOL_CONTROLLER = 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a;
    address internal constant FLK = 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;

    uint256 internal constant CREATOR_COIN_SUPPLY = 1_000_000e18;
}
