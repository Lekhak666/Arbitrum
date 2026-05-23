// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {MockERC20, HarnessIntentRegistry, MockRouter} from "../unit/Mocks.sol";
import {IntentRegistryHandler} from "./IntentRegistryHandler.sol";

// ─────────────────────────────────────────────────────────────────────────────
// IntentRegistryInvariantTest
//
// Run with:
//   forge test --match-contract IntentRegistryInvariantTest
//   forge test --match-contract IntentRegistryInvariantTest --invariant-runs 512
//
// Eight invariants verified:
//
//   I1  Token conservation  — registry balance == deposited - executed - refunded
//   I2  No double-execution — executed && cancelled is impossible
//   I3  Executed state is terminal — once executed, intent stays executed
//   I4  Cancelled state is terminal — once cancelled, intent stays cancelled
//   I5  Commitment integrity — revealed intents satisfy their original hash
//   I6  nextIntentId is monotonically non-decreasing
//   I7  Router allowance is always zero between transactions
//   I8  Refund accounting — ghost_totalRefunded matches on-chain cancelled+deposited intents
// ─────────────────────────────────────────────────────────────────────────────
contract IntentRegistryInvariantTest is StdInvariant, Test {
    HarnessIntentRegistry public registry;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;
    MockRouter public router;
    IntentRegistryHandler public handler;

    // For I3/I4 we snapshot executed/cancelled flags after each call.
    mapping(uint256 => bool) private prevExecuted;
    mapping(uint256 => bool) private prevCancelled;
    uint256 private prevNextId;

    function setUp() public {
        tokenIn = new MockERC20("TIN", "TIN");
        tokenOut = new MockERC20("TOUT", "TOUT");
        router = new MockRouter();
        registry = new HarnessIntentRegistry(address(router));

        // Register a dummy pool so the price-check path doesn't revert.
        address pool = address(0x1111111111111111111111111111111111111111);
        registry.registerPool(address(tokenIn), address(tokenOut), pool);

        // Build a small set of actors so intents are spread across multiple owners.
        address[] memory actors = new address[](3);
        actors[0] = address(0xA1);
        actors[1] = address(0xA2);
        actors[2] = address(0xA3);

        handler = new IntentRegistryHandler(registry, tokenIn, tokenOut, actors);

        // Tell Foundry to only call the handler; it drives the registry indirectly.
        targetContract(address(handler));
    }

    // =========================================================================
    // I1 — Token conservation
    //
    // Every tokenIn unit that entered the registry was deposited from a user.
    // It must either still sit in the registry, have been sent to the router
    // (executed), or returned to the user (cancelled / refunded).
    //
    //   registry.balanceOf == ghost_totalDeposited
    //                        - ghost_totalExecuted
    //                        - ghost_totalRefunded
    // =========================================================================
    function invariant_tokenConservation() public view {
        uint256 expected = handler.ghost_totalDeposited() - handler.ghost_totalExecuted()
            - handler.ghost_totalRefunded();

        assertEq(tokenIn.balanceOf(address(registry)), expected, "I1: token conservation violated");
    }

    // =========================================================================
    // I2 — Executed and cancelled are mutually exclusive
    //
    // An intent cannot be both executed and cancelled at the same time.
    // =========================================================================
    function invariant_executedAndCancelledMutuallyExclusive() public view {
        uint256 total = registry.nextIntentId();
        for (uint256 i = 0; i < total; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);
            assertFalse(intent.executed && intent.cancelled, "I2: intent is both executed and cancelled");
        }
    }

    // =========================================================================
    // I3 — Executed state is terminal
    //
    // Once intent.executed == true it must never flip back to false.
    // We maintain a shadow snapshot and check it is never violated.
    // =========================================================================
    function invariant_executedIsTerminal() public {
        uint256 total = registry.nextIntentId();
        for (uint256 i = 0; i < total; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);
            if (prevExecuted[i]) {
                assertTrue(intent.executed, "I3: executed flag was reset");
            }
            // Update snapshot.
            if (intent.executed) prevExecuted[i] = true;
        }
    }

    // =========================================================================
    // I4 — Cancelled state is terminal
    //
    // Once intent.cancelled == true it must never flip back to false.
    // =========================================================================
    function invariant_cancelledIsTerminal() public {
        uint256 total = registry.nextIntentId();
        for (uint256 i = 0; i < total; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);
            if (prevCancelled[i]) {
                assertTrue(intent.cancelled, "I4: cancelled flag was reset");
            }
            if (intent.cancelled) prevCancelled[i] = true;
        }
    }

    // =========================================================================
    // I5 — Commitment integrity
    //
    // For every revealed intent the stored commitmentHash must equal the
    // keccak256 of the revealed fields + stored expiry + known test secret.
    // This proves the contract never overwrites or corrupts the hash.
    // =========================================================================
    function invariant_commitmentHashIntegrity() public view {
        uint256 total = registry.nextIntentId();
        for (uint256 i = 0; i < total; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);
            if (!intent.revealed) continue;

            bytes32 expected = keccak256(
                abi.encodePacked(
                    intent.user,
                    intent.tokenIn,
                    intent.tokenOut,
                    intent.amountIn,
                    intent.targetPrice,
                    intent.minAmountOut,
                    intent.greaterThan,
                    intent.expiry,
                    handler.SECRET()
                )
            );

            assertEq(intent.commitmentHash, expected, "I5: commitmentHash mismatch after reveal");
        }
    }

    // =========================================================================
    // I6 — nextIntentId is monotonically non-decreasing
    // =========================================================================
    function invariant_nextIntentIdMonotonic() public {
        uint256 current = registry.nextIntentId();
        assertGe(current, prevNextId, "I6: nextIntentId decreased");
        prevNextId = current;
    }

    // =========================================================================
    // I7 — Router allowance is always zero between transactions
    //
    // executeIntentWithMockPrice must revoke the approval it grants.  Any
    // non-zero leftover would be a security vulnerability.
    // =========================================================================
    function invariant_routerAllowanceAlwaysZero() public view {
        assertEq(tokenIn.allowance(address(registry), address(router)), 0, "I7: leftover router allowance detected");
    }

    // =========================================================================
    // I8 — Refund accounting matches on-chain state
    //
    // ghost_totalRefunded must equal the sum of depositedAmount for every intent
    // that is both cancelled == true and was deposited.
    // =========================================================================
    function invariant_refundAccountingIsCorrect() public view {
        uint256 computedRefund;
        uint256 total = registry.nextIntentId();
        for (uint256 i = 0; i < total; i++) {
            IntentRegistry.TradeIntent memory intent = registry.getIntent(i);
            if (intent.cancelled && handler.ghost_wasDeposited(i)) {
                computedRefund += handler.ghost_depositedAmount(i);
            }
        }
        assertEq(
            handler.ghost_totalRefunded(),
            computedRefund,
            "I8: ghost_totalRefunded does not match on-chain cancelled+deposited intents"
        );
    }
}
