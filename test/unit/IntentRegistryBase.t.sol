// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20, HarnessIntentRegistry, MockRouter} from "./Mocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// IntentRegistryBase
//
// Shared setUp, constants, and helpers consumed by both the unit-test contract
// (IntentRegistryUnitTest) and the fuzz-test contract (IntentRegistryFuzzTest).
// Neither test contract is defined here; they just inherit this base.
// ─────────────────────────────────────────────────────────────────────────────
contract IntentRegistryBase is Test {
    // ── deployed contracts ────────────────────────────────────────────────
    HarnessIntentRegistry public registry;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockRouter public router;

    // ── named actors ──────────────────────────────────────────────────────
    address public constant USER = address(0xBEEF);
    address public constant KEEPER = address(0xCAFE);
    address public constant OTHER = address(0xDEAD);

    // ── dummy pool address (no real oracle needed) ────────────────────────
    address public constant POOL = address(0x1111111111111111111111111111111111111111);

    // ── default trade parameters ──────────────────────────────────────────
    uint256 public constant AMOUNT_IN = 1e18;
    uint256 public constant TARGET_PRICE = 2000e18;
    uint256 public constant MIN_AMOUNT_OUT = 1900e18;

    // ── known secret used whenever a specific secret is not under test ────
    bytes32 public constant SECRET = keccak256("shared_test_secret");

    // ─────────────────────────────────────────────────────────────────────
    function setUp() public virtual {
        tokenIn = new MockERC20("Token In", "TIN");
        tokenOut = new MockERC20("Token Out", "TOUT");
        router = new MockRouter();
        registry = new HarnessIntentRegistry(address(router));

        // Register the dummy pool so the harness can proceed past the pool check.
        registry.registerPool(address(tokenIn), address(tokenOut), POOL);

        // Give USER tokens and pre-approve the registry for the max amount.
        tokenIn.mint(USER, 1_000_000e18);
        vm.prank(USER);
        tokenIn.approve(address(registry), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────
    // _buildHash
    // Replicates the keccak256 the contract computes in revealIntent so tests
    // can build a valid commitment without duplicating the ABI-encoding logic.
    // ─────────────────────────────────────────────────────────────────────
    function _buildHash(
        address _user,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _targetPrice,
        uint256 _minAmountOut,
        bool _greaterThan,
        uint256 _expiry,
        bytes32 _secret
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                _user, _tokenIn, _tokenOut, _amountIn, _targetPrice, _minAmountOut, _greaterThan, _expiry, _secret
            )
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // _submit  — only submits the commitment
    // ─────────────────────────────────────────────────────────────────────
    function _submit(
        address caller,
        uint256 amountIn,
        uint256 targetPrice,
        uint256 minAmountOut,
        bool greaterThan,
        uint256 expiry,
        bytes32 secret
    ) internal returns (uint256 intentId) {
        bytes32 hash = _buildHash(
            caller,
            address(tokenIn),
            address(tokenOut),
            amountIn,
            targetPrice,
            minAmountOut,
            greaterThan,
            expiry,
            secret
        );
        vm.prank(caller);
        registry.submitIntent(hash, expiry);
        intentId = registry.nextIntentId() - 1;
    }

    // ─────────────────────────────────────────────────────────────────────
    // _submitAndReveal  — submit + reveal (no deposit)
    // ─────────────────────────────────────────────────────────────────────
    function _submitAndReveal(
        address caller,
        uint256 amountIn,
        uint256 targetPrice,
        uint256 minAmountOut,
        bool greaterThan,
        uint256 expiry,
        bytes32 secret
    ) internal returns (uint256 intentId) {
        intentId = _submit(caller, amountIn, targetPrice, minAmountOut, greaterThan, expiry, secret);
        vm.prank(caller);
        registry.revealIntent(
            intentId, address(tokenIn), address(tokenOut), amountIn, targetPrice, minAmountOut, greaterThan, secret
        );
    }

    // ─────────────────────────────────────────────────────────────────────
    // _fullSetup  — submit + reveal + deposit; the "happy path" state
    // Uses the module-level constants so callers don't repeat them.
    // ─────────────────────────────────────────────────────────────────────
    function _fullSetup(bool greaterThan, uint256 expiry) internal returns (uint256 intentId) {
        intentId = _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, greaterThan, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(intentId);
    }
}
