// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {IntentRegistryBase} from "./IntentRegistryBase.t.sol";
import {MockERC20, HarnessIntentRegistry} from "./Mocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// IntentRegistryUnitTest
//
// Every public / external function has its own section.
// Tests are grouped:
//   ✓ happy-path (should succeed)
//   ✗ revert paths (each error selector covered exactly once)
//   ⬡ side-effects (state changes, events, balances)
// ─────────────────────────────────────────────────────────────────────────────
contract IntentRegistryUnitTest is IntentRegistryBase {
    // =========================================================================
    // registerPool
    // =========================================================================

    function test_registerPool_storesBothDirections() public {
        address newPool = address(0x9999);
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");

        registry.registerPool(address(a), address(b), newPool);

        assertEq(registry.tokenPairPool(address(a), address(b)), newPool);
        assertEq(registry.tokenPairPool(address(b), address(a)), newPool);
    }

    function test_registerPool_emitsEvent() public {
        address newPool = address(0x8888);
        MockERC20 a = new MockERC20("A", "A");
        MockERC20 b = new MockERC20("B", "B");

        vm.expectEmit(true, true, true, false);
        emit IntentRegistry.PoolRegistered(address(a), address(b), newPool);
        registry.registerPool(address(a), address(b), newPool);
    }

    function test_registerPool_revertsIfCallerIsNotOwner() public {
        vm.expectRevert(IntentRegistry.IntentRegistry__NotContractOwner.selector);
        vm.prank(OTHER);
        registry.registerPool(address(tokenIn), address(tokenOut), POOL);
    }

    function test_registerPool_overwritesExistingPool() public {
        address p1 = address(111);
        address p2 = address(222);

        registry.registerPool(address(tokenIn), address(tokenOut), p1);
        registry.registerPool(address(tokenIn), address(tokenOut), p2);

        assertEq(registry.tokenPairPool(address(tokenIn), address(tokenOut)), p2);
    }

    // =========================================================================
    // submitIntent
    // =========================================================================

    function test_submitIntent_storesIntentCorrectly() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 hash = keccak256("commitment");

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);
        assertEq(intent.user, USER);
        assertEq(intent.commitmentHash, hash);
        assertEq(intent.expiry, expiry);
        assertEq(intent.tokenIn, address(0)); // placeholder until reveal
        assertFalse(intent.revealed);
        assertFalse(intent.executed);
        assertFalse(intent.deposited);
        assertFalse(intent.cancelled);
    }

    function test_submitIntent_incrementsNextIntentId() public {
        assertEq(registry.nextIntentId(), 0);

        uint256 expiry = block.timestamp + 1 days;
        vm.startPrank(USER);
        registry.submitIntent(keccak256("a"), expiry);
        registry.submitIntent(keccak256("b"), expiry);
        registry.submitIntent(keccak256("c"), expiry);
        vm.stopPrank();

        assertEq(registry.nextIntentId(), 3);
    }

    function test_submitIntent_emitsIntentSubmitted() public {
        vm.expectEmit(true, true, false, false);
        emit IntentRegistry.IntentSubmitted(0, USER);

        vm.prank(USER);
        registry.submitIntent(keccak256("x"), block.timestamp + 1);
    }

    function test_submitIntent_revertsIfExpiryEqualsNow() public {
        vm.expectRevert(IntentRegistry.IntentRegistry__ExpiryPassed.selector);
        vm.prank(USER);
        registry.submitIntent(keccak256("x"), block.timestamp);
    }

    function test_submitIntent_revertsIfExpiryInPast() public {
        vm.warp(1000);
        vm.expectRevert(IntentRegistry.IntentRegistry__ExpiryPassed.selector);
        vm.prank(USER);
        registry.submitIntent(keccak256("x"), 999);
    }

    // =========================================================================
    // revealIntent
    // =========================================================================

    function test_revealIntent_updatesAllFields() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.startPrank(USER);
        registry.submitIntent(hash, expiry);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, secret
        );
        vm.stopPrank();

        IntentRegistry.TradeIntent memory intent = registry.getIntent(0);
        assertEq(intent.tokenIn, address(tokenIn));
        assertEq(intent.tokenOut, address(tokenOut));
        assertEq(intent.amountIn, AMOUNT_IN);
        assertEq(intent.targetPrice, TARGET_PRICE);
        assertEq(intent.minAmountOut, MIN_AMOUNT_OUT);
        assertTrue(intent.greaterThan);
        assertTrue(intent.revealed);
    }

    function test_revealIntent_emitsIntentRevealed() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, false, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectEmit(true, false, false, false);
        emit IntentRegistry.IntentRevealed(0);

        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, false, secret
        );
    }

    function test_revealIntent_revertsIfNotOwner() public {
        uint256 expiry = block.timestamp + 1 days;
        vm.prank(USER);
        registry.submitIntent(keccak256("x"), expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotIntentOwner.selector);
        vm.prank(OTHER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, keccak256("x")
        );
    }

    function test_revealIntent_revertsIfAlreadyRevealed() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.startPrank(USER);
        registry.submitIntent(hash, expiry);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, secret
        );

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyRevealed.selector);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, secret
        );
        vm.stopPrank();
    }

    function test_revealIntent_revertsOnWrongSecret() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 hash = _buildHash(
            USER,
            address(tokenIn),
            address(tokenOut),
            AMOUNT_IN,
            TARGET_PRICE,
            MIN_AMOUNT_OUT,
            true,
            expiry,
            keccak256("correct")
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, keccak256("wrong")
        );
    }

    function test_revealIntent_revertsOnWrongAmountIn() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        registry.revealIntent(
            0,
            address(tokenIn),
            address(tokenOut),
            AMOUNT_IN + 1,
            TARGET_PRICE,
            MIN_AMOUNT_OUT, // tampered
            true,
            secret
        );
    }

    function test_revealIntent_revertsOnFlippedGreaterThan() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);
        vm.prank(USER);
        // greaterThan flipped to false
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, false, secret
        );
    }

    function test_revealIntent_revertsOnTamperedMinAmountOut() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
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
            0, // tampered minAmountOut
            true,
            secret
        );
    }

    function test_reveal_usesStoredExpiry_notCallerManipulatedExpiry() public {
        uint256 realExpiry = block.timestamp + 1 days;
        uint256 fakeExpiry = block.timestamp + 2 days;

        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, fakeExpiry, SECRET
        );

        vm.prank(USER);
        registry.submitIntent(hash, realExpiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__RevealHashMismatch.selector);

        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, SECRET
        );
    }

    function test_reveal_usesStoredExpiry_notCallerControlled() public {
        uint256 expiry = block.timestamp + 1 days;
        bytes32 secret = keccak256("s");

        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, secret
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.warp(expiry - 10);

        vm.prank(USER);
        registry.revealIntent(
            0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, secret
        );

        assertTrue(registry.getIntent(0).revealed);
    }

    // =========================================================================
    // depositIntentFunds
    // =========================================================================

    function test_deposit_transfersTokensToRegistry() public {
        uint256 expiry = block.timestamp + 1 days;
        _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);

        uint256 userBefore = tokenIn.balanceOf(USER);
        uint256 registryBefore = tokenIn.balanceOf(address(registry));

        vm.prank(USER);
        registry.depositIntentFunds(0);

        assertEq(tokenIn.balanceOf(USER), userBefore - AMOUNT_IN);
        assertEq(tokenIn.balanceOf(address(registry)), registryBefore + AMOUNT_IN);
        assertTrue(registry.getIntent(0).deposited);
    }

    function test_deposit_emitsFundsDeposited() public {
        uint256 expiry = block.timestamp + 1 days;
        _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);

        vm.expectEmit(true, false, false, true);
        emit IntentRegistry.FundsDeposited(0, AMOUNT_IN);

        vm.prank(USER);
        registry.depositIntentFunds(0);
    }

    function test_deposit_revertsIfNotOwner() public {
        uint256 expiry = block.timestamp + 1 days;
        _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotIntentOwner.selector);
        vm.prank(OTHER);
        registry.depositIntentFunds(0);
    }

    function test_deposit_revertsOnDoubleDeposit() public {
        uint256 expiry = block.timestamp + 1 days;
        _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);

        vm.startPrank(USER);
        registry.depositIntentFunds(0);

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyDeposited.selector);
        registry.depositIntentFunds(0);
        vm.stopPrank();
    }

    function test_deposit_beforeReveal_reverts() public {
        uint256 expiry = block.timestamp + 1 days;

        vm.prank(USER);
        registry.submitIntent(keccak256("x"), expiry);

        vm.expectRevert();

        vm.prank(USER);
        registry.depositIntentFunds(0);
    }

    function test_deposit_failedTransfer_doesNotPersistDeposit() public {
        MockERC20 evil = new MockERC20("E", "E");

        uint256 expiry = block.timestamp + 1 days;

        bytes32 hash = _buildHash(
            USER, address(evil), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET
        );

        vm.prank(USER);
        registry.submitIntent(hash, expiry);

        vm.prank(USER);
        registry.revealIntent(
            0, address(evil), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, SECRET
        );

        vm.expectRevert();

        vm.prank(USER);
        registry.depositIntentFunds(0);

        assertFalse(registry.getIntent(0).deposited);
    }

    // function test_deposit_beforeReveal_behavior() public {
    //     vm.prank(USER);
    //     registry.submitIntent(keccak256("x"), block.timestamp + 1 days);

    //     vm.prank(USER);

    //     // decide whether this should revert or silently succeed
    //     registry.depositIntentFunds(0);
    // }

    // =========================================================================
    // executeIntentWithMockPrice  (harness entry-point)
    // Tests every guard and side-effect of executeIntent without a live oracle.
    // =========================================================================

    // ── happy path: greaterThan = true ───────────────────────────────────────

    function test_execute_greaterThan_priceExactlyAtTarget_succeeds() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
        assertTrue(registry.getIntent(id).executed);
    }

    function test_execute_greaterThan_priceAboveTarget_succeeds() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE + 1e18);
        assertTrue(registry.getIntent(id).executed);
    }

    function test_execute_greaterThan_priceBelowTarget_reverts() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);

        vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE - 1);
    }

    // ── happy path: greaterThan = false ──────────────────────────────────────

    function test_execute_lessThan_priceExactlyAtTarget_succeeds() public {
        uint256 id = _fullSetup(false, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
        assertTrue(registry.getIntent(id).executed);
    }

    function test_execute_lessThan_priceBelowTarget_succeeds() public {
        uint256 id = _fullSetup(false, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE - 1);
        assertTrue(registry.getIntent(id).executed);
    }

    function test_execute_lessThan_priceAboveTarget_reverts() public {
        uint256 id = _fullSetup(false, block.timestamp + 1 days);

        vm.expectRevert(IntentRegistry.IntentRegistry__PriceConditionNotMet.selector);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE + 1);
    }

    // ── guard reverts ─────────────────────────────────────────────────────────

    function test_execute_revertsIfNotRevealed() public {
        uint256 expiry = block.timestamp + 1 days;
        vm.prank(USER);
        registry.submitIntent(keccak256("x"), expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentNotRevealed.selector);
        registry.executeIntentWithMockPrice(0, TARGET_PRICE + 1);
    }

    function test_execute_revertsIfAlreadyExecuted() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyExecuted.selector);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
    }

    function test_execute_revertsIfExpired() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentExpired.selector);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
    }

    function test_execute_revertsIfPoolNotRegistered() public {
        // Deploy a fresh registry with NO pool registered.
        HarnessIntentRegistry bare = new HarnessIntentRegistry(address(router));

        uint256 expiry = block.timestamp + 1 days;
        bytes32 hash = _buildHash(
            USER, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET
        );

        vm.prank(USER);
        tokenIn.approve(address(bare), type(uint256).max);

        vm.startPrank(USER);
        bare.submitIntent(hash, expiry);
        bare.revealIntent(0, address(tokenIn), address(tokenOut), AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, SECRET);
        bare.depositIntentFunds(0);
        vm.stopPrank();

        vm.expectRevert(IntentRegistry.IntentRegistry__PoolNotRegistered.selector);
        bare.executeIntentWithMockPrice(0, TARGET_PRICE);
    }

    // ── side-effects ─────────────────────────────────────────────────────────

    function test_execute_sendsCorrectParamsToRouter() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        assertEq(router.lastAmountIn(), AMOUNT_IN);
        assertEq(router.lastAmountOutMin(), MIN_AMOUNT_OUT);
        assertEq(router.lastRecipient(), USER);
        assertEq(router.lastPath0(), address(tokenIn));
        assertEq(router.lastPath1(), address(tokenOut));
    }

    function test_execute_routerAllowanceIsZeroAfterSwap() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        assertEq(tokenIn.allowance(address(registry), address(router)), 0);
    }

    function test_execute_outputTokensGoToUser() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        uint256 before = tokenOut.balanceOf(USER);

        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        // MockRouter mints 1-for-1, so USER should receive AMOUNT_IN of tokenOut.
        assertEq(tokenOut.balanceOf(USER), before + AMOUNT_IN);
    }

    function test_execute_anyoneCanCallAsKeeper() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        // OTHER is not the owner — execution should still succeed.
        vm.prank(OTHER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
        assertTrue(registry.getIntent(id).executed);
    }

    function test_execute_emitsIntentExecuted() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        uint256 mockPrice = TARGET_PRICE + 500e18;

        vm.expectEmit(true, false, false, true);
        emit IntentRegistry.IntentExecuted(id, mockPrice);

        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, mockPrice);
    }

    function test_execute_withoutDeposit_reverts() public {
        uint256 expiry = block.timestamp + 1 days;

        uint256 id = _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);

        vm.expectRevert();

        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);
    }

    function test_execute_preservesIntentData() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);

        IntentRegistry.TradeIntent memory before = registry.getIntent(id);

        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        IntentRegistry.TradeIntent memory after_ = registry.getIntent(id);

        assertEq(before.amountIn, after_.amountIn);
        assertEq(before.targetPrice, after_.targetPrice);
        assertEq(before.minAmountOut, after_.minAmountOut);
    }

    // =========================================================================
    // cancelIntent
    // =========================================================================

    // ── happy path ────────────────────────────────────────────────────────────

    function test_cancel_afterExpiry_refundsFullDeposit() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        uint256 before = tokenIn.balanceOf(USER);
        vm.prank(USER);
        registry.cancelIntent(id);

        assertEq(tokenIn.balanceOf(USER), before + AMOUNT_IN);
        assertTrue(registry.getIntent(id).cancelled);
    }

    function test_cancel_withoutDeposit_allowedBeforeExpiry() public {
        uint256 expiry = block.timestamp + 1 days;
        uint256 id = _submitAndReveal(USER, AMOUNT_IN, TARGET_PRICE, MIN_AMOUNT_OUT, true, expiry, SECRET);
        // No deposit — cancellation must succeed immediately.
        vm.prank(USER);
        registry.cancelIntent(id);
        assertTrue(registry.getIntent(id).cancelled);
    }

    function test_cancel_emitsIntentCancelled() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        vm.expectEmit(true, false, false, false);
        emit IntentRegistry.IntentCancelled(id);

        vm.prank(USER);
        registry.cancelIntent(id);
    }

    // ── revert paths ──────────────────────────────────────────────────────────

    function test_cancel_revertsIfNotOwner() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotIntentOwner.selector);
        vm.prank(OTHER);
        registry.cancelIntent(id);
    }

    function test_cancel_revertsIfDepositedAndNotYetExpired() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotYetExpired.selector);
        vm.prank(USER);
        registry.cancelIntent(id);
    }

    function test_cancel_revertsIfAlreadyExecuted() public {
        uint256 id = _fullSetup(true, block.timestamp + 1 days);
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id, TARGET_PRICE);

        vm.expectRevert(IntentRegistry.IntentRegistry__IntentAlreadyExecuted.selector);
        vm.prank(USER);
        registry.cancelIntent(id);
    }

    function test_cancel_revertsOnDoubleCancellation() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        vm.startPrank(USER);
        registry.cancelIntent(id);

        vm.expectRevert(IntentRegistry.IntentRegistry__AlreadyCancelled.selector);
        registry.cancelIntent(id);
        vm.stopPrank();
    }

    // ── boundary: expiry is exactly now ──────────────────────────────────────

    function test_cancel_revertsWhenExpiryEqualsBlockTimestamp() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);

        // Warp to exactly expiry.  Contract condition: expiry >= block.timestamp → revert.
        vm.warp(expiry);

        vm.expectRevert(IntentRegistry.IntentRegistry__NotYetExpired.selector);
        vm.prank(USER);
        registry.cancelIntent(id);
    }

    function test_cancel_succeedsOneSecondAfterExpiry() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 id = _fullSetup(true, expiry);
        vm.warp(expiry + 1);

        vm.prank(USER);
        registry.cancelIntent(id); // must not revert
        assertTrue(registry.getIntent(id).cancelled);
    }

    // =========================================================================
    // getIntent
    // =========================================================================

    function test_getIntent_returnsZeroStructForUnknownId() public view {
        IntentRegistry.TradeIntent memory intent = registry.getIntent(9999);
        assertEq(intent.user, address(0));
        assertEq(intent.amountIn, 0);
        assertFalse(intent.revealed);
        assertFalse(intent.executed);
    }

    // =========================================================================
    // Multi-intent isolation — IDs must never bleed state into each other
    // =========================================================================

    function test_multipleIntents_doNotInterfere() public {
        uint256 expiry = block.timestamp + 1 days;

        // Intent 0: greaterThan = true
        uint256 id0 = _fullSetup(true, expiry);
        // Intent 1: greaterThan = false (re-uses USER token balance)
        tokenIn.mint(USER, AMOUNT_IN);
        uint256 id1 = _fullSetup(false, expiry);

        assertEq(id0, 0);
        assertEq(id1, 1);

        // Execute intent 0 only.
        vm.prank(KEEPER);
        registry.executeIntentWithMockPrice(id0, TARGET_PRICE);

        assertTrue(registry.getIntent(id0).executed);
        assertFalse(registry.getIntent(id1).executed);
    }
}
