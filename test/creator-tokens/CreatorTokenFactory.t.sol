// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { CreatorTokenFactory } from "../../src/creator-tokens/core/CreatorTokenFactory.sol";
import { BondingCurveFactory } from "../../src/creator-tokens/core/BondingCurveFactory.sol";
import { CreatorCoinFactory } from "../../src/creator-tokens/core/CreatorCoinFactory.sol";
import { BondingCurve } from "../../src/creator-tokens/curve/BondingCurve.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract MockFLK is ERC20 {
    constructor() ERC20("Fleek Token", "FLK") {
        _mint(msg.sender, 1_000_000_000e18);
    }
}

contract MockUniversalHook {
    function registerToken(address, address, address) external {
        // Mock implementation
    }
}

contract CreatorTokenFactoryTest is Test {
    CreatorTokenFactory public factory;
    BondingCurveFactory public bondingCurveFactory;
    CreatorCoinFactory public creatorCoinFactory;
    BondingCurve public bondingCurveImpl;
    MockFLK public flk;

    address public foundation = address(0x1);
    address public creator = address(0x2);
    address public user = address(0x3);
    address public deploymentAuthorizer = Config.COIN_DEPLOYMENT_AUTHORIZER();
    address public mockHookAddress;

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork(vm.envString("BASE_RPC"));

        // Deploy mock FLK and etch it to the expected address
        MockFLK tempFlk = new MockFLK();
        vm.etch(Config.FLK(), address(tempFlk).code);
        flk = MockFLK(Config.FLK());

        // Deploy mock universal hook with correct flags
        MockUniversalHook tempHook = new MockUniversalHook();
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        mockHookAddress = address(flags);
        vm.etch(mockHookAddress, address(tempHook).code);

        // Deploy bonding curve implementation
        bondingCurveImpl = new BondingCurve();

        // Deploy sub-factories
        bondingCurveFactory =
            new BondingCurveFactory(foundation, address(bondingCurveImpl), mockHookAddress);

        creatorCoinFactory = new CreatorCoinFactory(foundation);

        // Deploy main factory - it now uses Config.COIN_DEPLOYMENT_AUTHORIZER() as owner
        factory = new CreatorTokenFactory(address(bondingCurveFactory), address(creatorCoinFactory));

        // Transfer ownership of sub-factories to main factory
        vm.startPrank(foundation);
        bondingCurveFactory.transferOwnership(address(factory));
        creatorCoinFactory.transferOwnership(address(factory));
        vm.stopPrank();

        vm.label(foundation, "Foundation");
        vm.label(creator, "Creator");
        vm.label(user, "User");
        vm.label(deploymentAuthorizer, "DeploymentAuthorizer");
        vm.label(address(factory), "CreatorTokenFactory");
    }

    function test_SetBondingCurveFactory_OnlyOwner() public {
        address newFactory = address(0x999);

        // Non-owner should fail
        vm.startPrank(user);
        vm.expectRevert();
        factory.setBondingCurveFactory(newFactory);
        vm.stopPrank();

        // Owner (deploymentAuthorizer) should succeed
        vm.startPrank(deploymentAuthorizer);
        factory.setBondingCurveFactory(newFactory);
        assertEq(address(factory.bondingCurveFactory()), newFactory);
        vm.stopPrank();
    }

    function test_SetCreatorCoinFactory_OnlyOwner() public {
        address newFactory = address(0x999);

        // Non-owner should fail
        vm.startPrank(user);
        vm.expectRevert();
        factory.setCreatorCoinFactory(newFactory);
        vm.stopPrank();

        // Owner (deploymentAuthorizer) should succeed
        vm.startPrank(deploymentAuthorizer);
        factory.setCreatorCoinFactory(newFactory);
        assertEq(address(factory.creatorCoinFactory()), newFactory);
        vm.stopPrank();
    }

    function test_DeployNew_TotalSupplyCorrect() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        // Use the correct owner (deploymentAuthorizer) to call deployNew
        vm.startPrank(deploymentAuthorizer);
        vm.recordLogs();
        factory.deployNew(name, symbol, vestingStart, vestingDuration, cliffDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        address tokenAddress;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (tokenAddress,,) = abi.decode(entries[i].data, (address, address, address));
                break;
            }
        }

        CreatorCoin token = CreatorCoin(tokenAddress);

        // Total supply should equal sum of all allocations
        uint256 expectedTotal =
            Config.BONDING_CURVE_ALLOCATION + Config.CREATOR_ALLOCATION
            + Config.CREATOR_FUND_ALLOCATION + Config.FAN_POOL_ALLOCATION;

        assertEq(token.totalSupply(), expectedTotal, "Total supply should match sum of allocations");
        vm.stopPrank();
    }
}
