// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

/**
 * @title FactoryConfig
 * @notice Chain-aware configuration for creator token deployments
 * @dev Returns different addresses based on chain ID (Base mainnet: 8453, Base Sepolia: 84532)
 */
library Config {
    // Chain IDs
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant BASE_SEPOLIA = 84532;

    // Token allocations (same across all chains)
    uint256 internal constant BONDING_CURVE_ALLOCATION = 450_000e18;
    uint256 internal constant CREATOR_ALLOCATION = 250_000e18;
    uint256 internal constant CREATOR_FUND_ALLOCATION = 50_000e18;
    uint256 internal constant FAN_POOL_ALLOCATION = 250_000e18;

    // Bonding curve parameters (same across all chains)
    uint256 internal constant GRADUATION_THRESHOLD = 20_675e18;
    uint256 internal constant BASE_PRICE = 1e15;

    // Fee tiers (same across all chains)
    uint256 internal constant FEE_TIER_1 = 250_000e18;
    uint256 internal constant FEE_TIER_2 = 150_000e18;
    uint256 internal constant FEE_TIER_3 = 50_000e18;

    // Token decimals (same across all chains)
    uint8 internal constant FLK_DECIMALS = 18;
    uint8 internal constant CREATOR_COIN_DECIMALS = 18;

    // Token supply (same across all chains)
    uint256 internal constant CREATOR_COIN_SUPPLY = 1_000_000e18;

    /**
     * @notice Returns the foundation address for the current chain
     * @return Foundation address
     */
    function FOUNDATION() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885; // Testnet
        }
        return 0x5719061AD5052C1f2E4c942c68F35935adD31f7E; // Mainnet
    }

    /**
     * @notice Returns the fan pool controller address for the current chain
     * @return Fan pool controller address
     */
    function FAN_POOL_CONTROLLER() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0xF3191119E5Be5795d7DD3D60ABb949064CDcB885; // Testnet
        }
        return 0x491193C8C2BA55503dBf83eB608E69E93b9Ba96a; // Mainnet
    }

    /**
     * @notice Returns the FLK token address for the current chain
     * @return FLK token address
     */
    function FLK() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return 0x88DB73F86c7025608420f447ae003b7CD3286E71; // Testnet FLK
        }
        return 0xE0969ec84456b7e4d3Dd2181fB5265EDbB63F7BD; // Mainnet FLK
    }
}
