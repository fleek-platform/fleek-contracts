// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title Config
 * @notice Chain-aware configuration for creator token deployments
 * @dev Returns different addresses based on chain ID (Base mainnet: 8453, Base Sepolia: 84532)
 */
library Config {
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant BASE_SEPOLIA = 84532;

    uint256 internal constant BONDING_CURVE_ALLOCATION = 450_000e18;
    uint256 internal constant CREATOR_ALLOCATION = 250_000e18;
    uint256 internal constant CREATOR_FUND_ALLOCATION = 50_000e18;
    uint256 internal constant FAN_POOL_ALLOCATION = 250_000e18;

    uint256 internal constant GRADUATION_THRESHOLD = 20_675e18;
    uint256 internal constant BASE_PRICE = 1e15;

    uint256 internal constant FEE_TIER_1 = 250_000e18;
    uint256 internal constant FEE_TIER_2 = 150_000e18;
    uint256 internal constant FEE_TIER_3 = 50_000e18;

    uint64 internal constant VESTING_DURATION = 1825 days;
    uint64 internal constant VESTING_CLIFF = 35 days;

    uint8 internal constant FLK_DECIMALS = 18;
    uint8 internal constant CREATOR_COIN_DECIMALS = 18;

    uint256 internal constant CREATOR_COIN_SUPPLY = 1_000_000e18;

    /**
     * @notice Returns the foundation address for the current chain
     */
    function FOUNDATION() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
        }
        return 0xD9c34f98B34AF12f4b3802574bD106FFAa7cF72b;
    }

    function COIN_DEPLOYMENT_AUTHORIZER() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0x951a4fCfBC765Ec41c7f45811d1E7009EB62d3c9;
        }

        return 0xDc29caBf6b172A9a42DB77102331BCf16c06bE63;
    }

    /**
     * @notice Returns the FLK token address for the current chain
     */
    function FLK() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0x88DB73F86c7025608420f447ae003b7CD3286E71;
        }
        return 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD;
    }
}
