// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library BaseUniswapDeployments {
    // Chain IDs
    uint256 internal constant BASE_MAINNET = 8453;
    uint256 internal constant BASE_SEPOLIA = 84532;

    // Mainnet addresses
    address internal constant MAINNET_POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant MAINNET_POSITION_DESCRIPTOR =
        0x25D093633990DC94BeDEeD76C8F3CDaa75f3E7D5;
    address internal constant MAINNET_POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant MAINNET_QUOTER = 0x0d5e0F971ED27FBfF6c2837bf31316121532048D;
    address internal constant MAINNET_STATE_VIEW = 0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71;
    address internal constant MAINNET_UNIVERSAL_ROUTER = 0x6fF5693b99212Da76ad316178A184AB56D299b43;

    // Testnet addresses (Base Sepolia)
    address internal constant TESTNET_POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address internal constant TESTNET_POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address internal constant TESTNET_UNIVERSAL_ROUTER = 0x492E6456D9528771018DeB9E87ef7750EF184104;

    // Permit2 is the same across chains
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function POOL_MANAGER() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return TESTNET_POOL_MANAGER;
        }
        return MAINNET_POOL_MANAGER;
    }

    function POSITION_MANAGER() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return TESTNET_POSITION_MANAGER;
        }
        return MAINNET_POSITION_MANAGER;
    }

    function UNIVERSAL_ROUTER() internal view returns (address) {
        if (block.chainid == BASE_SEPOLIA) {
            return TESTNET_UNIVERSAL_ROUTER;
        }
        return MAINNET_UNIVERSAL_ROUTER;
    }

    function POSITION_DESCRIPTOR() internal view returns (address) {
        return MAINNET_POSITION_DESCRIPTOR;
    }

    function QUOTER() internal view returns (address) {
        return MAINNET_QUOTER;
    }

    function STATE_VIEW() internal view returns (address) {
        return MAINNET_STATE_VIEW;
    }
}
