// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { BondingCurveFactory } from "../../src/creator-tokens/core/BondingCurveFactory.sol";
import { BondingCurve } from "../../src/creator-tokens/curve/BondingCurve.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract MockUniversalHook {
    function registerToken(address, address, address) external {
        // Mock implementation
    }
}

contract BondingCurveFactoryTest is Test {
    BondingCurveFactory public factory;
    BondingCurve public implementation;
    address public mockHookAddress;

    address public owner = address(0x1);
    address public creator = address(0x2);
    address public nonOwner = address(0x3);

    function setUp() public {
        // Deploy mock universal hook with correct flags
        MockUniversalHook tempHook = new MockUniversalHook();
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        mockHookAddress = address(flags);
        vm.etch(mockHookAddress, address(tempHook).code);

        // Deploy implementation
        implementation = new BondingCurve();

        // Deploy factory
        factory = new BondingCurveFactory(owner, address(implementation), mockHookAddress);

        vm.label(owner, "Owner");
        vm.label(creator, "Creator");
        vm.label(nonOwner, "NonOwner");
    }

    function test_Deploy_OnlyOwner() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        // Non-owner should fail
        vm.startPrank(nonOwner);
        vm.expectRevert();
        factory.deploy(creator, address(token), address(vesting));
        vm.stopPrank();

        // Owner should succeed
        vm.startPrank(owner);
        BondingCurve curve = factory.deploy(creator, address(token), address(vesting));
        assertTrue(address(curve) != address(0), "Bonding curve should be deployed");
        vm.stopPrank();
    }

    function test_Deploy_CreatesClone() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve1 = factory.deploy(creator, address(token), address(vesting));
        BondingCurve curve2 = factory.deploy(creator, address(token), address(vesting));
        vm.stopPrank();

        // Should create different clones
        assertTrue(address(curve1) != address(curve2), "Should create different clones");

        // Both should be initialized and not be the implementation
        assertTrue(
            address(curve1) != address(implementation), "Curve1 should not be implementation"
        );
        assertTrue(
            address(curve2) != address(implementation), "Curve2 should not be implementation"
        );
    }

    function test_Deploy_InitializesCorrectly() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve = factory.deploy(creator, address(token), address(vesting));
        vm.stopPrank();

        // Verify initialization
        (
            address _creator,
            address _creatorToken,
            uint256 _slope,
            address _vestingWallet,
            address _universalHook,
            uint256 _deploymentTimestamp,
            bool _graduated
        ) = curve.metadata();

        assertEq(_creator, creator, "Creator should match");
        assertEq(_creatorToken, address(token), "Token should match");
        assertGt(_slope, 0, "Slope should be set");
        assertEq(_vestingWallet, address(vesting), "Vesting wallet should match");
        assertEq(_universalHook, mockHookAddress, "Universal hook should match");
        assertEq(_deploymentTimestamp, block.timestamp, "Timestamp should be current");
        assertFalse(_graduated, "Should not be graduated initially");
        assertEq(curve.creatorTokensSold(), 0, "No tokens sold initially");
    }

    function test_Deploy_UsesCorrectParameters() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve = factory.deploy(creator, address(token), address(vesting));
        vm.stopPrank();

        (,, uint256 slope,,,,) = curve.metadata();

        // Slope should be calculated from Config parameters
        // We can verify it's non-zero and reasonable
        assertGt(slope, 0, "Slope should be positive");
    }

    function test_Deploy_MultipleDeployments() public {
        address creator1 = address(0x100);
        address creator2 = address(0x200);

        CreatorCoin token1 = new CreatorCoin("Token1", "TK1");
        CreatorCoin token2 = new CreatorCoin("Token2", "TK2");

        CreatorVesting vesting1 =
            new CreatorVesting(creator1, uint64(block.timestamp), 365 days, 30 days);
        CreatorVesting vesting2 =
            new CreatorVesting(creator2, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve1 = factory.deploy(creator1, address(token1), address(vesting1));
        BondingCurve curve2 = factory.deploy(creator2, address(token2), address(vesting2));
        vm.stopPrank();

        // Verify each curve has correct creator
        (address _creator1,,,,,,) = curve1.metadata();
        (address _creator2,,,,,,) = curve2.metadata();

        assertEq(_creator1, creator1, "Curve1 should have creator1");
        assertEq(_creator2, creator2, "Curve2 should have creator2");
    }

    function test_Deploy_GasEfficiency() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);

        uint256 gasBefore = gasleft();
        factory.deploy(creator, address(token), address(vesting));
        uint256 gasUsed = gasBefore - gasleft();

        // Clones should be gas efficient (typically < 100k gas)
        // This is much cheaper than deploying a new contract directly
        assertTrue(gasUsed < 500000, "Clone deployment should be gas efficient");

        vm.stopPrank();
    }

    function test_Deploy_ClonesAreIndependent() public {
        CreatorCoin token1 = new CreatorCoin("Token1", "TK1");
        CreatorCoin token2 = new CreatorCoin("Token2", "TK2");

        CreatorVesting vesting1 =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);
        CreatorVesting vesting2 =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve1 = factory.deploy(creator, address(token1), address(vesting1));
        BondingCurve curve2 = factory.deploy(creator, address(token2), address(vesting2));
        vm.stopPrank();

        // Verify they have different state
        (, address token1Addr,,,,,) = curve1.metadata();
        (, address token2Addr,,,,,) = curve2.metadata();

        assertEq(token1Addr, address(token1), "Curve1 should have token1");
        assertEq(token2Addr, address(token2), "Curve2 should have token2");
        assertTrue(token1Addr != token2Addr, "Curves should have different tokens");
    }

    function test_Deploy_ReturnsValidContract() public {
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting =
            new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        vm.startPrank(owner);
        BondingCurve curve = factory.deploy(creator, address(token), address(vesting));
        vm.stopPrank();

        // Verify it's a valid contract with code
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(curve)
        }
        assertGt(codeSize, 0, "Deployed curve should have code");
    }
}
