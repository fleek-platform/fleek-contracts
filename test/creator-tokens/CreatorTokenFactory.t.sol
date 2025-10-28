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

        // Deploy main factory
        factory = new CreatorTokenFactory(
            foundation, address(bondingCurveFactory), address(creatorCoinFactory)
        );

        // Transfer ownership of sub-factories to main factory
        vm.startPrank(foundation);
        bondingCurveFactory.transferOwnership(address(factory));
        creatorCoinFactory.transferOwnership(address(factory));
        vm.stopPrank();

        vm.label(foundation, "Foundation");
        vm.label(creator, "Creator");
        vm.label(user, "User");
        vm.label(address(factory), "CreatorTokenFactory");
    }

    function test_InitialState() public view {
        assertEq(address(factory.bondingCurveFactory()), address(bondingCurveFactory));
        assertEq(address(factory.creatorCoinFactory()), address(creatorCoinFactory));
        assertEq(factory.owner(), foundation);
    }

    function test_DeployNew_Success() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.expectEmit(false, false, false, false);
        emit CreatorTokenFactory.TokenDeployed(address(0), address(0), address(0));

        factory.deployNew(name, symbol, vestingStart, vestingDuration, cliffDuration);

        // Verify token name was registered
        assertTrue(factory.tokenNames(name), "Token name should be registered");
    }

    function test_DeployNew_CreatesAllComponents() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.recordLogs();
        factory.deployNew(name, symbol, vestingStart, vestingDuration, cliffDuration);

        // Extract addresses from event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        address tokenAddress;
        address bondingCurveAddress;
        address vestingAddress;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (tokenAddress, bondingCurveAddress, vestingAddress) =
                    abi.decode(entries[i].data, (address, address, address));
                break;
            }
        }

        // Verify all components were created
        assertTrue(tokenAddress != address(0), "Token should be deployed");
        assertTrue(bondingCurveAddress != address(0), "Bonding curve should be deployed");
        assertTrue(vestingAddress != address(0), "Vesting should be deployed");

        // Verify token properties
        CreatorCoin token = CreatorCoin(tokenAddress);
        assertEq(token.name(), name, "Token name should match");
        assertEq(token.symbol(), symbol, "Token symbol should match");

        assertEq(
            token.balanceOf(bondingCurveAddress),
            Config.BONDING_CURVE_ALLOCATION,
            "Bonding curve should receive allocation"
        );

        assertEq(
            token.balanceOf(vestingAddress),
            Config.CREATOR_ALLOCATION,
            "Vesting should receive creator allocation"
        );

        assertEq(
            token.balanceOf(Config.FOUNDATION()),
            Config.CREATOR_FUND_ALLOCATION,
            "Foundation should receive allocation"
        );

        assertEq(
            token.balanceOf(Config.FAN_POOL_CONTROLLER()),
            Config.FAN_POOL_ALLOCATION,
            "Fan pool should receive allocation"
        );

        assertEq(
            factory.bondingCurveFor(tokenAddress),
            bondingCurveAddress,
            "Bonding curve should be registered"
        );
    }

    function test_DeployNew_RevertsOnDuplicateName() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        // First deployment should succeed
        factory.deployNew(name, symbol, vestingStart, vestingDuration, cliffDuration);

        // Second deployment with same name should fail
        vm.expectRevert(CreatorTokenFactory.TokenNameExists.selector);
        factory.deployNew(name, "TEST2", vestingStart, vestingDuration, cliffDuration);
    }

    function test_DeployNew_AllowsDifferentNames() public {
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        // Deploy first token
        factory.deployNew("Token One", "ONE", vestingStart, vestingDuration, cliffDuration);

        // Deploy second token with different name should succeed
        factory.deployNew("Token Two", "TWO", vestingStart, vestingDuration, cliffDuration);

        assertTrue(factory.tokenNames("Token One"), "First token name should be registered");
        assertTrue(factory.tokenNames("Token Two"), "Second token name should be registered");
    }

    function test_SetBondingCurveFactory_OnlyOwner() public {
        address newFactory = address(0x999);

        // Non-owner should fail
        vm.startPrank(user);
        vm.expectRevert();
        factory.setBondingCurveFactory(newFactory);
        vm.stopPrank();

        // Owner should succeed
        vm.startPrank(foundation);
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

        // Owner should succeed
        vm.startPrank(foundation);
        factory.setCreatorCoinFactory(newFactory);
        assertEq(address(factory.creatorCoinFactory()), newFactory);
        vm.stopPrank();
    }

    function test_BondingCurveFor_Mapping() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

        vm.recordLogs();
        factory.deployNew(name, symbol, vestingStart, vestingDuration, cliffDuration);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        address tokenAddress;
        address bondingCurveAddress;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenDeployed(address,address,address)")) {
                (tokenAddress, bondingCurveAddress,) =
                    abi.decode(entries[i].data, (address, address, address));
                break;
            }
        }

        // Verify mapping is correct
        assertEq(
            factory.bondingCurveFor(tokenAddress),
            bondingCurveAddress,
            "BondingCurveFor should map token to curve"
        );
    }

    function test_DeployNew_TotalSupplyCorrect() public {
        string memory name = "Test Token";
        string memory symbol = "TEST";
        uint64 vestingStart = uint64(block.timestamp);
        uint64 vestingDuration = 365 days;
        uint64 cliffDuration = 30 days;

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
    }
}
