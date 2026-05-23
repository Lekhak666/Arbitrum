// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {Test} from "forge-std/Test.sol";
import {IntentRegistryBase} from "../unit/IntentRegistryBase.t.sol";

// ─────────────────────────────────────────────────────────────────────────────
// IntentRegistryFuzzTest
//
// Each test function accepts fuzz inputs and uses vm.assume / bound to keep
// them in sensible ranges.  Properties tested:
//
//   P1  submitIntent:  any future expiry is accepted; past/present always reverts.
//   P2  revealIntent:  any single-field mutation in the commitment causes revert.
//   P3  executeIntent: price condition boundary is exact for both directions.
//   P4  executeIntent: expired intents always revert regardless of price.
//   P5  depositFunds:  registry balance delta equals exactly amountIn.
//   P6  cancelIntent:  post-expiry cancel always returns exactly amountIn.
//   P7  cancelIntent:  pre-expiry cancel on deposited intent always reverts.
// ─────────────────────────────────────────────────────────────────────────────
contract IntentRegistryFuzzTest is Test, IntentRegistryBase {
    // =========================================================================
    // P1 — submitIntent expiry boundary
    // =========================================================================

    /// Any offset > 0 from now must be accepted.
    function testFuzz_submit_acceptsAnyFutureExpiry(uint256 offset) public {
        offset = bound(offset, 1, 365 days * 200);
        uint256 expiry = block.timestamp + offset;

        vm.prank(USER);
        registry.submitIntent(keccak256("x"), expiry);

        assertEq(registry.nextIntentId(), 1);
    }

    /// Any timestamp <= now must revert.
    function testFuzz_submit_rejectsAnyPastOrPresentExpiry(uint256 expiry) public {
        expiry = bound(expiry, 0, block.timestamp);

        vm.expectRevert(IntentRegistry.IntentRegistry__ExpiryPassed.selector);
        vm.prank(USER);
        registry.submitIntent(keccak256("x"), expiry);
    }

    // =========================================================================
    // P2 — revealIntent: commitment hash is binding for every field
    // =========================================================================

    /// Mutating amountIn causes a hash mismatch.
    function testFuzz_reveal_tamperedAmountIn_alwaysReverts(uint256 real, uint256 tampered) public {
        real = bound(real, 1, type(uint128).max);
        tampered = bound(tampered, 1, type(uint128).max);
        vm.assume(real != tampered);

        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), real, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), tampered, TARGET_PRICE, MIN_AMOUNT_OUT, true, secret
        );
    }

    /// Mutating targetPrice causes a hash mismatch.
    function testFuzz_reveal_tamperedTargetPrice_alwaysReverts(uint256 real, uint256 tampered) public {
        real = bound(real, 1, type(uint128).max);
        tampered = bound(tampered, 1, type(uint128).max);
        vm.assume(real != tampered);

        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, real, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(0, address(tokenIn), address(tokenOut), AMOUNT_IN, tampered, MIN_AMOUNT_OUT, true, secret);
    }

    /// Mutating minAmountOut causes a hash mismatch (slippage parameter is binding).
    function testFuzz_reveal_tamperedMinAmountOut_alwaysReverts(uint256 real, uint256 tampered) public {
        real = bound(real, 0, type(uint128).max);
        tampered = bound(tampered, 0, type(uint128).max);
        vm.assume(real != tampered);

        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash =
            _buildHash(USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, real, true, expiry, secret);

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, tampered, true, secret);
    }

    /// Any wrong secret causes a hash mismatch.
    function testFuzz_reveal_wrongSecret_alwaysReverts(bytes32 correct, bytes32 wrong) public {
        vm.assume(correct != wrong);

        uint256 expiry = block.timestamp + 1 days;
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, correct
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, wrong
        );
    }

    /// Flipping greaterThan causes a hash mismatch.
    function testFuzz_reveal_flippedGreaterThan_alwaysReverts(bool committed) public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER,
            address(tokenIn),
            address(tokenOut),
            AMOUNT_IN,
            TARGET_PRICE,
            MIN_AMOUNT_OUT,
            committed,
            expiry,
            secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(
            0,
            address(tokenIn),
            address(tokenOut),
            AMOUNT_IN,
            TARGET_PRICE,
            MIN_AMOUNT_OUT,
            !committed,
            secret // flipped
        );
    }

    // =========================================================================
    // P3 — executeIntent price condition is exact
    // =========================================================================

    /// greaterThan=true: executes iff price >= target (and reverts otherwise).
    function testFuzz_execute_greaterThan_conditionIsExact(uint256 amountIn, uint256 targetPrice, uint256 currentPrice)
        public
    {
        amountIn = bound(amountIn, 1, type(uint128).max);
        targetPrice = bound(targetPrice, 1, type(uint128).max);

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, amountIn, targetPrice, 0, true, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        if (currentPrice >= targetPrice) {
            vm.prank(KEEPER);
            registry.executeIntentWithMockPrice(id, currentPrice);
            assertTrue(registry.getIntent(id).executed);
        } else {
            vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);
            vm.prank(KEEPER);
            registry.executeIntentWithMockPrice(id, currentPrice);
            assertFalse(registry.getIntent(id).executed);
        }
    }

    /// greaterThan=false: executes iff price <= target (and reverts otherwise).
    function testFuzz_execute_lessThan_conditionIsExact(uint256 amountIn, uint256 targetPrice, uint256 currentPrice)
        public
    {
        amountIn = bound(amountIn, 1, type(uint128).max);
        targetPrice = bound(targetPrice, 1, type(uint128).max);

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, amountIn, targetPrice, 0, false, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        if (currentPrice <= targetPrice) {
            vm.prank(KEEPER);
            registry.executeIntentWithMockPrice(id, currentPrice);
            assertTrue(registry.getIntent(id).executed);
        } else {
            vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);
            vm.prank(KEEPER);
            registry.executeIntentWithMockPrice(id, currentPrice);
            assertFalse(registry.getIntent(id).executed);
        }
    }

    // =========================================================================
    // P4 — executeIntent: always reverts after expiry regardless of price
    // =========================================================================

    function testFuzz_execute_postExpiry_alwaysReverts(
        uint256 amountIn,
        uint256 secondsAfterExpiry,
        uint256 currentPrice
    ) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        secondsAfterExpiry = bound(secondsAfterExpiry, 1, 365 days);

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 2 hours;
        uint256 id = _submitAndReveal(USER, amountIn, TARGET_PRICE, 0, true, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        vm.warp(expiry + secondsAfterExpiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentExpired.selector);
        registry.executeIntentWithMockPrice(id, currentPrice);
    }

    // =========================================================================
    // P5 — depositIntentFunds: balance delta equals exactly amountIn
    // =========================================================================

    function testFuzz_deposit_balanceDeltaEqualsAmountIn(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, amountIn, TARGET_PRICE, 0, true, expiry, SECRET);

        uint256 registryBefore = tokenIn.balanceOf(address(registry));
        uint256 userBefore = tokenIn.balanceOf(USER);

        vm.prank(USER);
        registry.depositIntentFunds(id);

        assertEq(tokenIn.balanceOf(address(registry)), registryBefore + amountIn);
        assertEq(tokenIn.balanceOf(USER), userBefore - amountIn);
    }

    // =========================================================================
    // P6 — cancelIntent: post-expiry cancel returns exactly amountIn
    // =========================================================================

    function testFuzz_cancel_postExpiry_refundsExactAmountIn(uint256 amountIn, uint256 secondsAfterExpiry) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        secondsAfterExpiry = bound(secondsAfterExpiry, 1, 365 days);

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _submitAndReveal(USER, amountIn, TARGET_PRICE, 0, true, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        vm.warp(expiry + secondsAfterExpiry);

        uint256 before = tokenIn.balanceOf(USER);
        vm.prank(USER);
        registry.cancelIntent(id);

        assertEq(tokenIn.balanceOf(USER), before + amountIn);
    }

    // =========================================================================
    // P7 — cancelIntent: pre-expiry on deposited intent always reverts
    // =========================================================================

    function testFuzz_cancel_preExpiry_deposited_alwaysReverts(uint256 amountIn, uint256 secondsBeforeExpiry) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        secondsBeforeExpiry = bound(secondsBeforeExpiry, 0, 1 days - 1);

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, amountIn, TARGET_PRICE, 0, true, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        // Warp to any point strictly before expiry.
        vm.warp(block.timestamp + secondsBeforeExpiry);
        vm.assume(block.timestamp <= expiry); // belt-and-suspenders

        vm.expectRevert(IntentRegistry.IntentRegistry__NotYetExpired.selector);
        vm.prank(USER);
        registry.cancelIntent(id);
    }

    // =========================================================================
    // Extra — router always receives the committed minAmountOut (slippage binding)
    // =========================================================================

    function testFuzz_execute_routerReceivesCommittedMinAmountOut(uint256 amountIn, uint256 minAmountOut) public {
        amountIn = bound(amountIn, 1, type(uint128).max);
        minAmountOut = bound(minAmountOut, 0, amountIn); // sane range

        tokenIn.mint(USER, amountIn);

        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, amountIn, TARGET_PRICE, minAmountOut, true, expiry, SECRET);
        vm.prank(USER);
        registry.depositIntentFunds(id);

        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE); // price meets condition

        assertEq(router.lastAmountOutMin(), minAmountOut);
    }
}
