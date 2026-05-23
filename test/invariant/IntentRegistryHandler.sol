// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {MockERC20, HarnessIntentRegistry} from "../unit/Mocks.sol";

// ─────────────────────────────────────────────────────────────────────────────
// IntentRegistryHandler
//
// Drives the fuzzer.  The invariant test contract calls targetContract on this,
// so Foundry will call only its public functions.
//
// Shadow accounting kept here lets the invariant assertions in the test contract
// verify global properties without iterating over all intents on every call.
// ─────────────────────────────────────────────────────────────────────────────
contract IntentRegistryHandler is Test {
    // ── contracts under test ──────────────────────────────────────────────
    HarnessIntentRegistry public registry;
    MockERC20 public tokenIn;
    MockERC20 public tokenOut;

    // ── actors: the fuzzer will pick one each call ─────────────────────────
    address[] public actors;

    // ── known secret so the invariant test can re-derive hashes ───────────
    bytes32 public constant SECRET = keccak256("handler_secret");

    // ── shadow accounting ─────────────────────────────────────────────────
    uint256 public ghostTotalDeposited; // Σ amountIn deposited
    uint256 public ghostTotalExecuted; // Σ amountIn whose swap has gone through
    uint256 public ghostTotalRefunded; // Σ amountIn returned via cancelIntent

    // Per-intent deposit tracking (needed by invariant assertions).
    mapping(uint256 => uint256) public ghostDepositedAmount;
    mapping(uint256 => bool) public ghostWasDeposited;

    // ── local state ───────────────────────────────────────────────────────
    uint256 private constant MAX_AMOUNT = type(uint128).max;

    constructor(HarnessIntentRegistry _registry, MockERC20 _tokenIn, MockERC20 _tokenOut, address[] memory _actors) {
        registry = _registry;
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        actors = _actors;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helper: pick an actor deterministically from a seed.
    // ─────────────────────────────────────────────────────────────────────
    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helper: compute the same commitment hash as the contract.
    // ─────────────────────────────────────────────────────────────────────
    function _buildHash(
        address user,
        uint256 amountIn,
        uint256 targetPrice,
        uint256 minAmountOut,
        bool greaterThan,
        uint256 expiry
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                user,
                address(tokenIn),
                address(tokenOut),
                amountIn,
                targetPrice,
                minAmountOut,
                greaterThan,
                expiry,
                SECRET
            )
        );
    }

    // =========================================================================
    // ACTION: submitRevealDeposit
    // Atomically submits, reveals, and deposits a new intent so the state
    // space moves quickly into interesting territory.
    // =========================================================================
    function submitRevealDeposit(
        uint256 actorSeed,
        uint256 amountIn,
        uint256 targetPrice,
        bool greaterThan,
        uint256 expiryOffset
    ) external {
        amountIn = bound(amountIn, 1, MAX_AMOUNT);
        targetPrice = bound(targetPrice, 1, MAX_AMOUNT);
        expiryOffset = bound(expiryOffset, 1, 365 days);

        address user = _actor(actorSeed);
        uint256 expiry = block.timestamp + expiryOffset;

        // Fund the actor and approve.
        tokenIn.mint(user, amountIn);
        vm.prank(user);
        tokenIn.approve(address(registry), type(uint256).max);

        bytes32 hash = _buildHash(user, amountIn, targetPrice, 0, greaterThan, expiry);

        vm.startPrank(user);
        registry.submitIntent(hash, expiry);
        uint256 id = registry.nextIntentId() - 1;
        registry.revealIntent(id, address(tokenIn), address(tokenOut), amountIn, targetPrice, 0, greaterThan, SECRET);
        registry.depositIntentFunds(id);
        vm.stopPrank();

        // Shadow bookkeeping.
        ghostTotalDeposited += amountIn;
        ghostDepositedAmount[id] = amountIn;
        ghostWasDeposited[id] = true;
    }

    // =========================================================================
    // ACTION: executeIntent
    // Picks a valid, executable intent and calls executeIntentWithMockPrice with
    // a price that satisfies the condition (guaranteed execution path so the
    // state actually changes and ghost counters can be updated).
    // =========================================================================
    function executeIntent(uint256 intentSeed, uint256 priceSeed) external {
        uint256 total = registry.nextIntentId();
        if (total == 0) return;

        uint256 id = intentSeed % total;
        IntentRegistry.TradeIntent memory intent = registry.getIntent(id);

        if (!intent.revealed) return;
        if (intent.executed) return;
        if (intent.cancelled) return;
        if (block.timestamp > intent.expiry) return;

        // Construct a price that satisfies the condition.
        uint256 price = intent.greaterThan
            ? bound(priceSeed, intent.targetPrice, MAX_AMOUNT)
            : bound(priceSeed, 0, intent.targetPrice);

        try registry.executeIntentWithMockPrice(id, price) {
            ghostTotalExecuted += ghostDepositedAmount[id];
        } catch {
            // Racing with a cancel or time edge — harmless.
        }
    }

    // =========================================================================
    // ACTION: cancelIntent
    // Cancels a deposited, expired intent and updates the refund counter.
    // Also exercises the no-deposit cancellation path.
    // =========================================================================
    function cancelIntent(uint256 intentSeed) external {
        uint256 total = registry.nextIntentId();
        if (total == 0) return;

        uint256 id = intentSeed % total;
        IntentRegistry.TradeIntent memory intent = registry.getIntent(id);

        if (intent.executed) return;
        if (intent.cancelled) return;

        // If deposited, warp past expiry to allow cancellation.
        if (intent.deposited && block.timestamp <= intent.expiry) {
            vm.warp(intent.expiry + 1);
        }

        vm.prank(intent.user);
        try registry.cancelIntent(id) {
            if (ghostWasDeposited[id]) {
                ghostTotalRefunded += ghostDepositedAmount[id];
            }
        } catch {
            // Ignore: another action may have already cancelled it.
        }
    }

    // =========================================================================
    // ACTION: warpTime
    // Advances time to create expiry conditions.
    // =========================================================================
    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 0, 30 days);
        vm.warp(block.timestamp + seconds_);
    }
}
