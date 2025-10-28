// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { BondingCurve } from "../../src/creator-tokens/curve/BondingCurve.sol";
import { CreatorCoin } from "../../src/creator-tokens/tokens/CreatorCoin.sol";
import { CreatorVesting } from "../../src/creator-tokens/tokens/CreatorVesting.sol";
import { Config } from "../../src/creator-tokens/libraries/Config.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Hooks } from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title BondingCurveEdgeCasesTest
 * @notice Tests edge cases and error conditions to improve branch coverage
 */
contract BondingCurveEdgeCasesTest is Test {
    BondingCurve public bondingCurve;
    CreatorCoin public creatorCoin;
    CreatorVesting public vestingWallet;

    address public creator = address(0x1);
    address public user1 = address(0x2);

    uint256 constant BONDING_CURVE_MAX_SUPPLY = Config.BONDING_CURVE_ALLOCATION / 2;
    uint256 constant TOTAL_TOKENS_TO_CURVE = Config.BONDING_CURVE_ALLOCATION;

    // Mock ERC20 that can be configured to fail transfers
    MockERC20WithFailure public mockFLK;
    MockERC20WithFailure public mockCreatorToken;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC"));

        // Deploy mock universal hook with correct flags
        MockUniversalHook tempHook = new MockUniversalHook();
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        address mockHookAddress = address(flags);
        vm.etch(mockHookAddress, address(tempHook).code);

        vm.label(creator, "Creator");
        vm.label(user1, "User1");
    }

    // ============ TEST: RE-INITIALIZATION ============

    function test_Revert_AlreadyInitialized() public {
        // Deploy a regular token and bonding curve for this test
        CreatorCoin token = new CreatorCoin("Test", "TEST");
        CreatorVesting vesting = new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);
        BondingCurve curve = new BondingCurve();
        
        // Get mock hook address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        address mockHookAddress = address(flags);
        MockUniversalHook tempHook = new MockUniversalHook();
        vm.etch(mockHookAddress, address(tempHook).code);

        // Initialize once
        curve.initialize(
            creator,
            address(token),
            Config.GRADUATION_THRESHOLD,
            Config.BASE_PRICE,
            BONDING_CURVE_MAX_SUPPLY,
            address(vesting),
            mockHookAddress
        );

        // Try to initialize again - should revert
        vm.expectRevert(BondingCurve.AlreadyInitialized.selector);
        curve.initialize(
            creator,
            address(token),
            Config.GRADUATION_THRESHOLD,
            Config.BASE_PRICE,
            BONDING_CURVE_MAX_SUPPLY,
            address(vesting),
            mockHookAddress
        );
    }

    // ============ TEST: TOKEN TRANSFER FAILURES ============

    function test_Revert_Buy_FLKTransferFails() public {
        // Create a bonding curve with mock tokens that can fail
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Give user1 some FLK and approve
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        // Configure FLK to fail on transferFrom
        flk.setShouldFail(true);

        // Try to buy - should revert with TokenTransferFailed
        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.buy(100e18, 0);
    }

    function test_Revert_Buy_CreatorTokenTransferFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Give user1 some FLK and approve
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        // Transfer tokens to curve
        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);

        // Configure creator token to fail on transfer (not transferFrom)
        token.setShouldFailTransfer(true);

        // Try to buy - should revert with TokenTransferFailed
        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.buy(100e18, 0);
    }

    function test_Revert_BuyExactTokens_FLKTransferFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        // Configure FLK to fail
        flk.setShouldFail(true);

        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.buyExactTokens(1000e18, type(uint256).max);
    }

    function test_Revert_BuyExactTokens_CreatorTokenTransferFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);
        token.setShouldFailTransfer(true);

        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.buyExactTokens(1000e18, type(uint256).max);
    }

    function test_Revert_Sell_CreatorTokenTransferFromFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Setup: Buy some tokens first
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);

        vm.prank(user1);
        curve.buy(100e18, 0);

        // Get user1's token balance
        uint256 userTokenBalance = token.balanceOf(user1);

        // Now configure token to fail on transferFrom
        token.setShouldFail(true);
        vm.prank(user1);
        token.approve(address(curve), type(uint256).max);

        // Try to sell
        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.sell(userTokenBalance / 2, 0);
    }

    function test_Revert_Sell_FLKTransferFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Setup: Buy some tokens first
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);

        vm.prank(user1);
        curve.buy(100e18, 0);

        uint256 userTokenBalance = token.balanceOf(user1);

        // Configure FLK to fail on transfer (not transferFrom)
        flk.setShouldFailTransfer(true);

        vm.prank(user1);
        token.approve(address(curve), type(uint256).max);

        // Try to sell
        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.sell(userTokenBalance / 2, 0);
    }

    function test_Revert_SellExactTokens_CreatorTokenTransferFromFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Setup: Buy some tokens first
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);

        vm.prank(user1);
        curve.buy(100e18, 0);

        // Configure token to fail
        token.setShouldFail(true);
        vm.prank(user1);
        token.approve(address(curve), type(uint256).max);

        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.sellExactTokens(10e18, type(uint256).max);
    }

    function test_Revert_SellExactTokens_FLKTransferFails() public {
        (BondingCurve curve, MockERC20WithFailure token, MockERC20WithFailure flk) = 
            _setupCurveWithMockTokens();

        // Setup: Buy some tokens first
        flk.mint(user1, 1000e18);
        vm.prank(user1);
        flk.approve(address(curve), type(uint256).max);

        token.mint(address(curve), TOTAL_TOKENS_TO_CURVE);

        vm.prank(user1);
        curve.buy(100e18, 0);

        // Configure FLK to fail on transfer
        flk.setShouldFailTransfer(true);

        vm.prank(user1);
        token.approve(address(curve), type(uint256).max);

        vm.prank(user1);
        vm.expectRevert(BondingCurve.TokenTransferFailed.selector);
        curve.sellExactTokens(10e18, type(uint256).max);
    }

    // ============ HELPER FUNCTIONS ============

    function _setupCurveWithMockTokens() internal returns (
        BondingCurve curve,
        MockERC20WithFailure token,
        MockERC20WithFailure flk
    ) {
        // Deploy mock tokens
        token = new MockERC20WithFailure("Creator Token", "CT");
        flk = new MockERC20WithFailure("FLK", "FLK");

        // Etch FLK to expected address
        vm.etch(Config.FLK(), address(flk).code);
        flk = MockERC20WithFailure(Config.FLK());

        // Deploy vesting wallet
        CreatorVesting vesting = new CreatorVesting(creator, uint64(block.timestamp), 365 days, 30 days);

        // Deploy mock hook
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        address mockHookAddress = address(flags);
        MockUniversalHook tempHook = new MockUniversalHook();
        vm.etch(mockHookAddress, address(tempHook).code);

        // Deploy and initialize bonding curve
        curve = new BondingCurve();
        curve.initialize(
            creator,
            address(token),
            Config.GRADUATION_THRESHOLD,
            Config.BASE_PRICE,
            BONDING_CURVE_MAX_SUPPLY,
            address(vesting),
            mockHookAddress
        );

        return (curve, token, flk);
    }
}

// ============ MOCK CONTRACTS ============

contract MockFLK is ERC20 {
    constructor() ERC20("Fleek Token", "FLK") {
        _mint(msg.sender, 1_000_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockUniversalHook {
    function registerToken(address, address, address) external {
        // Do nothing
    }
}

/**
 * @notice Mock ERC20 that can be configured to fail on transfers
 */
contract MockERC20WithFailure is ERC20 {
    bool public shouldFail;
    bool public shouldFailTransfer;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setShouldFailTransfer(bool _shouldFail) external {
        shouldFailTransfer = _shouldFail;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (shouldFailTransfer) {
            return false;
        }
        return super.transfer(to, amount);
    }
}
