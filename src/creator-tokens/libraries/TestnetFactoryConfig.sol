// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title TestnetFactoryConfig
 * @notice Configuration for Base Sepolia testnet deployments
 * @dev Uses testnet addresses for foundation, fan pool controller, and FLK token
 */
library TestnetFactoryConfig {
    // Token allocations (same as mainnet)
    uint256 internal constant BONDING_CURVE_ALLOCATION = 450_000e18;
    uint256 internal constant CREATOR_ALLOCATION = 250_000e18;
    uint256 internal constant CREATOR_FUND_ALLOCATION = 50_000e18;
    uint256 internal constant FAN_POOL_ALLOCATION = 250_000e18;

    // Bonding curve parameters (same as mainnet)
    uint256 internal constant GRADUATION_THRESHOLD = 20_675e18;
    uint256 internal constant BASE_PRICE = 1e15;

    // Fee tiers (same as mainnet)
    uint256 internal constant FEE_TIER_1 = 250_000e18;
    uint256 internal constant FEE_TIER_2 = 150_000e18;
    uint256 internal constant FEE_TIER_3 = 50_000e18;

    // Testnet addresses
    address internal constant FOUNDATION = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address internal constant FAN_POOL_CONTROLLER = 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885;
    address internal constant FLK = 0x88DB73F86c7025608420f447ae003b7CD3286E71;
    
    // Token decimals (same as mainnet)
    uint8 internal constant FLK_DECIMALS = 18;
    uint8 internal constant CREATOR_COIN_DECIMALS = 18;

    // Token supply (same as mainnet)
    uint256 internal constant CREATOR_COIN_SUPPLY = 1_000_000e18;
}
