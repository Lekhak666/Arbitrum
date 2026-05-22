// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouter} from "./interfaces/IRouter.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/**
 * @title IntentRegistry
 *
 * @author Khushi Barnwal, Nayab Khan
 *
 * @notice A registry for managing trade intents with a commit-reveal scheme.
 * Users submit hashed commitments, reveal them later, and execute them when
 * on-chain TWAP price conditions are met.
 *
 * @dev All six security issues from the original audit have been addressed:
 *   #1 — Caller-supplied price replaced with Uniswap V3 30-min TWAP.
 *   #2 — CEI order fixed: intent.executed set before any external call.
 *   #3 — Double-deposit prevented with a deposited flag (CEI-ordered).
 *   #4 — cancelIntent added with executed/deposited guards and fund return.
 *   #5 — Zero slippage fixed: minAmountOut committed in hash, used in swap.
 *   #6 — Stale router approval cleared to 0 after every swap.
 */
contract IntentRegistry {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error IntentRegistry__ExpiryPassed();
    error IntentRegistry__NotIntentOwner();
    error IntentRegistry__AlreadyRevealed();
    error IntentRegistry__RevealHashMismatch();
    error IntentRegistry__IntentNotRevealed();
    error IntentRegistry__AlreadyExecuted();
    error IntentRegistry__IntentExpired();
    error IntentRegistry__PriceConditionNotMet();
    error IntentRegistry__TransferInDepositIntentFailed();
    error IntentRegistry__AlreadyDeposited();
    error IntentRegistry__AlreadyCancelled();
    error IntentRegistry__IntentAlreadyExecuted(); // for cancelIntent path
    error IntentRegistry__NotYetExpired();
    error IntentRegistry__CancelTransferFailed();
    error IntentRegistry__PoolNotRegistered();
    error IntentRegistry__NotContractOwner();

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice TWAP window used for all oracle price reads.
    /// 30 minutes makes the price hard to manipulate within a single block.
    uint32 public constant TWAP_INTERVAL = 1800;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    IRouter public immutable ROUTER;

    /// @notice Deployer — used only to register Uniswap V3 pools.
    address public immutable contractOwner;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 public nextIntentId;

    /// @notice FIX #1 — maps tokenIn → tokenOut → Uniswap V3 pool address.
    /// Both directions are registered so the lookup is order-independent.
    mapping(address => mapping(address => address)) public tokenPairPool;

    mapping(uint256 => TradeIntent) public intents;

    // -------------------------------------------------------------------------
    // Struct
    // -------------------------------------------------------------------------

    struct TradeIntent {
        address user; // Wallet that submitted the intent
        address tokenIn; // Token being sold
        address tokenOut; // Token being bought
        uint256 amountIn; // Exact amount of tokenIn to sell
        uint256 targetPrice; // TWAP quote (tokenOut for amountIn tokenIn) that must be met
        uint256 minAmountOut; // FIX #5 — hard slippage floor passed to the router
        bool greaterThan; // true → execute when TWAP >= targetPrice; false → TWAP <= targetPrice
        uint256 expiry; // Unix timestamp after which execution is forbidden
        bytes32 commitmentHash; // keccak256 of all intent fields + secret
        bool revealed;
        bool executed;
        bool deposited; // FIX #3 — prevents double-deposit
        bool cancelled;
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event IntentSubmitted(uint256 indexed intentId, address indexed user);
    event IntentRevealed(uint256 indexed intentId);
    event FundsDeposited(uint256 indexed intentId, uint256 amount);
    event IntentExecuted(uint256 indexed intentId, uint256 twapPrice);
    event IntentCancelled(uint256 indexed intentId); // FIX #4
    event PoolRegistered(address indexed tokenA, address indexed tokenB, address indexed pool);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _router) {
        ROUTER = IRouter(_router);
        contractOwner = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Admin — pool registry
    // -------------------------------------------------------------------------

    /**
     * @notice Register the Uniswap V3 pool that will be used as the TWAP
     *         oracle for a given token pair.  Only the deployer can call this.
     *
     * @param tokenA One token in the pair.
     * @param tokenB The other token in the pair.
     * @param pool   The Uniswap V3 pool address for tokenA/tokenB.
     */
    function registerPool(address tokenA, address tokenB, address pool) external {
        if (msg.sender != contractOwner) {
            revert IntentRegistry__NotContractOwner();
        }
        // Register in both directions so lookup works regardless of argument order.
        tokenPairPool[tokenA][tokenB] = pool;
        tokenPairPool[tokenB][tokenA] = pool;
        emit PoolRegistered(tokenA, tokenB, pool);
    }

    // -------------------------------------------------------------------------
    // Submit Commitment
    // -------------------------------------------------------------------------

    /**
     * @notice Submit a hashed commitment.  No trade details are revealed yet.
     *
     * @param _commitmentHash  keccak256(user, tokenIn, tokenOut, amountIn,
     *                         targetPrice, minAmountOut, greaterThan, expiry, secret)
     * @param _expiry          Unix timestamp; must be strictly in the future.
     */
    function submitIntent(bytes32 _commitmentHash, uint256 _expiry) external {
        if (_expiry <= block.timestamp) revert IntentRegistry__ExpiryPassed();

        intents[nextIntentId] = TradeIntent({
            user: msg.sender,
            tokenIn: address(0),
            tokenOut: address(0),
            amountIn: 0,
            targetPrice: 0,
            minAmountOut: 0,
            greaterThan: true,
            expiry: _expiry,
            commitmentHash: _commitmentHash,
            revealed: false,
            executed: false,
            deposited: false,
            cancelled: false
        });

        emit IntentSubmitted(nextIntentId, msg.sender);
        nextIntentId++;
    }

    // -------------------------------------------------------------------------
    // Reveal Intent
    // -------------------------------------------------------------------------

    /**
     * @notice Reveal the plaintext details that were committed in submitIntent.
     *         The contract recomputes the hash and reverts on any mismatch.
     *
     * NOTE: minAmountOut is now part of the commitment hash (FIX #5).
     *       Your off-chain hash helper must include it; see _hash() in the tests.
     *
     * @param minAmountOut  FIX #5 — minimum tokenOut from the swap.
     *                      Committed in the hash so it cannot be front-run.
     */
    function revealIntent(
        uint256 intentId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 targetPrice,
        uint256 minAmountOut,
        bool greaterThan,
        bytes32 secret
    ) external {
        TradeIntent storage intent = intents[intentId];

        if (msg.sender != intent.user) revert IntentRegistry__NotIntentOwner();
        if (intent.revealed) revert IntentRegistry__AlreadyRevealed();

        // Recompute hash from caller-supplied plaintext + stored expiry.
        // Using the stored expiry (not a caller argument) prevents expiry substitution attacks.
        bytes32 computedHash = keccak256(
            abi.encodePacked(
                msg.sender,
                tokenIn,
                tokenOut,
                amountIn,
                targetPrice,
                minAmountOut, // FIX #5 — minAmountOut is part of the commitment
                greaterThan,
                intent.expiry,
                secret
            )
        );

        if (computedHash != intent.commitmentHash) {
            revert IntentRegistry__RevealHashMismatch();
        }

        intent.tokenIn = tokenIn;
        intent.tokenOut = tokenOut;
        intent.amountIn = amountIn;
        intent.targetPrice = targetPrice;
        intent.minAmountOut = minAmountOut;
        intent.greaterThan = greaterThan;
        intent.revealed = true;

        emit IntentRevealed(intentId);
    }

    // -------------------------------------------------------------------------
    // Deposit
    // -------------------------------------------------------------------------

    /**
     * @notice Pull amountIn tokens from the user into the registry.
     *         FIX #3 — the deposited flag is set before the external transferFrom
     *         call (CEI), making double-deposit impossible.
     */
    function depositIntentFunds(uint256 id) external {
        TradeIntent storage intent = intents[id];

        if (msg.sender != intent.user) revert IntentRegistry__NotIntentOwner();
        if (intent.deposited) revert IntentRegistry__AlreadyDeposited();

        // FIX #3 — effect before interaction.
        intent.deposited = true;

        bool ok = IERC20(intent.tokenIn).transferFrom(msg.sender, address(this), intent.amountIn);
        if (!ok) revert IntentRegistry__TransferInDepositIntentFailed();

        emit FundsDeposited(id, intent.amountIn);
    }

    // -------------------------------------------------------------------------
    // Execute Intent
    // -------------------------------------------------------------------------

    /**
     * @notice Execute a revealed intent when the TWAP price condition is met.
     *
     * FIX #1 — price comes from Uniswap V3 TWAP, not from the caller.
     * FIX #2 — intent.executed is set before any external call (CEI).
     * FIX #5 — minAmountOut (committed by the user) is passed to the router.
     * FIX #6 — router approval is reset to 0 after the swap.
     */
    function executeIntent(uint256 intentId) external {
        TradeIntent storage intent = intents[intentId];

        if (!intent.revealed) revert IntentRegistry__IntentNotRevealed();
        if (intent.executed) revert IntentRegistry__AlreadyExecuted();
        if (block.timestamp > intent.expiry) {
            revert IntentRegistry__IntentExpired();
        }

        // ---- FIX #1 — Uniswap V3 TWAP oracle --------------------------------
        address pool = tokenPairPool[intent.tokenIn][intent.tokenOut];
        if (pool == address(0)) revert IntentRegistry__PoolNotRegistered();

        // consult() returns the time-weighted average tick over TWAP_INTERVAL seconds.
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, TWAP_INTERVAL);

        // getQuoteAtTick converts the tick to "how many tokenOut for amountIn tokenIn".
        // Casting amountIn to uint128 is safe for token amounts up to ~3.4 × 10^38.
        uint256 currentPrice =
            OracleLibrary.getQuoteAtTick(arithmeticMeanTick, uint128(intent.amountIn), intent.tokenIn, intent.tokenOut);
        // ----------------------------------------------------------------------

        bool conditionMet = intent.greaterThan ? currentPrice >= intent.targetPrice : currentPrice <= intent.targetPrice;

        if (!conditionMet) revert IntentRegistry__PriceConditionNotMet();

        // ---- FIX #2 — CEI: write state before all external calls ------------
        intent.executed = true;
        // ---------------------------------------------------------------------

        // ---- FIX #5 — real slippage floor passed to router ------------------
        IERC20(intent.tokenIn).approve(address(ROUTER), intent.amountIn);

        address[] memory path = new address[](2);
        path[0] = intent.tokenIn;
        path[1] = intent.tokenOut;

        ROUTER.swapExactTokensForTokens(
            intent.amountIn,
            intent.minAmountOut, // was 0; now the user's committed minimum
            path,
            intent.user,
            block.timestamp + 300
        );

        // ---- FIX #6 — reset stale approval to zero --------------------------
        // Leftover allowance is dangerous if the router is ever upgraded or
        // compromised; setting it back to 0 closes that window.
        IERC20(intent.tokenIn).approve(address(ROUTER), 0);
        // ---------------------------------------------------------------------

        emit IntentExecuted(intentId, currentPrice);
    }

    // -------------------------------------------------------------------------
    // Cancel Intent
    // -------------------------------------------------------------------------

    /**
     * @notice FIX #4 — lets the intent owner recover deposited funds after expiry.
     *
     * Rules:
     *  - Only the intent owner can cancel.
     *  - Cannot cancel an already-executed intent (funds already swapped).
     *  - Cannot cancel twice.
     *  - If funds were deposited, they are returned only after the intent has
     *    expired (prevents cancelling while a keeper could still execute).
     *  - If funds were never deposited, the intent can be cancelled at any time
     *    (no funds to return, no keeper conflict).
     */
    function cancelIntent(uint256 intentId) external {
        TradeIntent storage intent = intents[intentId];

        if (msg.sender != intent.user) revert IntentRegistry__NotIntentOwner();
        if (intent.cancelled) revert IntentRegistry__AlreadyCancelled();
        if (intent.executed) revert IntentRegistry__IntentAlreadyExecuted();

        // If funds are already sitting in this contract, wait for expiry first.
        // Pre-deposit cancellations (e.g. change of mind before deposit) are allowed anytime.
        if (intent.deposited && intent.expiry >= block.timestamp) {
            revert IntentRegistry__NotYetExpired();
        }

        intent.cancelled = true;

        // Only attempt transfer if there are actually funds to return.
        if (intent.deposited) {
            bool ok = IERC20(intent.tokenIn).transfer(msg.sender, intent.amountIn);
            if (!ok) revert IntentRegistry__CancelTransferFailed();
        }

        emit IntentCancelled(intentId);
    }

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------

    function getIntent(uint256 intentId) external view returns (TradeIntent memory) {
        return intents[intentId];
    }
}
