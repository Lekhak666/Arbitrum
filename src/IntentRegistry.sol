// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRouter} from "./interfaces/IRouter.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {OracleLibrary} from "./libraries/OracleLibrary.sol";

/**
 * @title IntentRegistry
 *
 * @author Khushi Barnwal, Nayab Khan
 *
 * @notice A registry for managing trade intents with a commit-reveal scheme.
 * Users can submit trade intents as hashed commitments, reveal them later with details, and execute them if conditions are met.
 *
 *  @dev The contract ensures that only the owner of the intent can reveal it and that the intent is executed only if it has been revealed, has not expired, and meets the target price conditions.
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
    error IntentRegistry__IntentAlreadyExecuted();
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
    address public immutable CONTRACT_OWNER;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    uint256 public nextIntentId;

    // -------------------------------------------------------------------------
    // Mappings and Structs
    // -------------------------------------------------------------------------

    ///@notice Mapping from token pair to Uniswap V3 pool address.
    // maps tokenIn → tokenOut → Uniswap V3 pool address.
    // contract supports ANY pair
    mapping(address => mapping(address => address)) public tokenPairPool;

    ///@notice Mapping from intent ID to TradeIntent struct, storing all details of each intent. This is the main storage for intents in the contract.
    mapping(uint256 intentId => TradeIntent) public intents;

    struct TradeIntent {
        address user; // Owner of the intent
        address tokenIn; // Token the user wants to sell
        address tokenOut; // Token the user wants to buy
        uint256 amountIn; // Amount of tokenIn the user wants to sell
        uint256 targetPrice; // Target price for the trade (e.g., price of tokenIn in terms of tokenOut)
        uint256 minAmountOut; // Minimum amount of tokenOut the user expects to receive (used for slippage protection)
        bool greaterThan; // If true, execute when current price >= targetPrice; if false, execute when current price <= targetPrice
        uint256 expiry; // Timestamp after which the intent can no longer be executed
        ///@notice keccak256 of all intent fields + secret for the commit-reveal scheme, stored on-chain at submission and used for verification at reveal. This ensures that users cannot change their intent details after submission without invalidating their commitment.
        bytes32 commitmentHash; // Hash of the intent details for the commit-reveal scheme : HIDDEN ORDER HASH
        bool revealed; // Whether the intent has been revealed
        bool executed; // Whether the intent has been executed
        bool deposited; // Whether the user has deposited the funds for the intent
        bool cancelled; // Whether the intent has been cancelled
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event IntentSubmitted(uint256 indexed intentId, address indexed user); // Emitted when a new intent is submitted

    event IntentRevealed(uint256 indexed intentId); // Emitted when an intent is revealed

    event FundsDeposited(uint256 indexed id, uint256 amount);

    event IntentExecuted(uint256 indexed intentId, uint256 twapPrice); // Emitted when an intent is executed

    event IntentCancelled(uint256 indexed intentId); // Emitted when an intent is cancelled

    event PoolRegistered(address indexed tokenA, address indexed tokenB, address indexed pool); // Emitted when a Uniswap V3 pool is registered for a token pair

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    constructor(address _router) {
        ROUTER = IRouter(_router);
        CONTRACT_OWNER = msg.sender;
    }

    // -------------------------------------------------------------------------
    // Admin — pool registry
    // -------------------------------------------------------------------------

    /**
     * @notice Register the Uniswap V3 pool that will be used as the TWAP
     *         oracle for a given token pair.
     * @dev Only the deployer can call this.
     * @param tokenA One token in the pair.
     * @param tokenB The other token in the pair.
     * @param pool   The Uniswap V3 pool address for tokenA/tokenB.
     */
    function registerPool(address tokenA, address tokenB, address pool) external {
        if (msg.sender != CONTRACT_OWNER) {
            revert IntentRegistry__NotContractOwner();
        }
        // Register in both directions so lookup works regardless of argument order.
        tokenPairPool[tokenA][tokenB] = pool;
        tokenPairPool[tokenB][tokenA] = pool;
        emit PoolRegistered(tokenA, tokenB, pool);
    }

    // --------------------------
    // Submit Commitment
    // --------------------------

    /**
     * @notice Submit intent, an external state-modifying contract function.
     *
     * @dev Submit a hashed commitment.  No trade details are revealed yet.
     *
     * @param _commitmentHash keccak256(user, tokenIn, tokenOut, amountIn, targetPrice, greaterThan, expiry, secret) (bytes32).
     * @param _expiry Unix timestamp; must be strictly in the future.
     *
     * @custom:signature submitIntent(bytes32,uint256)
     * @custom:selector 0xe22321bc
     */
    function submitIntent(bytes32 _commitmentHash, uint256 _expiry) external {
        if (_expiry <= block.timestamp) {
            revert IntentRegistry__ExpiryPassed();
        }

        intents[nextIntentId] = TradeIntent({
            user: msg.sender, // Wallet calling submitIntent is the owner of the intent
            tokenIn: address(0), // Placeholder, will be set on reveal
            tokenOut: address(0), // Placeholder, will be set on reveal
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

    // --------------------------
    // Reveal Intent
    // --------------------------

    /**
     * @notice Reveal intent, an external state-modifying contract function.
     *
     * @dev Reveal the plaintext details that were committed in submitIntent.
     *         The contract recomputes the hash and reverts on any mismatch.
     *
     * @param intentId The intent id (uint256).
     * @param tokenIn The token in address.
     * @param tokenOut The token out address.
     * @param amountIn The amount in (uint256).
     * @param targetPrice The target price (uint256).
     * @param minAmountOut The minimum amount out for slippage protection (uint256).
     *                      Committed in the hash so it cannot be front-run.
     * @param greaterThan The greater than (bool).
     * @param secret The secret (bytes32).
     *
     * @custom:signature revealIntent(uint256,address,address,uint256,uint256,bool,bytes32)
     * @custom:selector 0xaad8f8b4
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
        TradeIntent storage intent = intents[intentId]; // Fetch the intent from storage (real blockchain storage reference)

        if (msg.sender != intent.user) {
            revert IntentRegistry__NotIntentOwner();
        }

        if (intent.revealed) {
            revert IntentRegistry__AlreadyRevealed();
        }

        // Recompute hash from caller-supplied plaintext + stored expiry.
        // Using the stored expiry (not a caller argument) prevents expiry substitution attacks.
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 computedHash = keccak256(
            abi.encodePacked(
                msg.sender, tokenIn, tokenOut, amountIn, targetPrice, minAmountOut, greaterThan, intent.expiry, secret
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

        emit IntentRevealed(intentId); // Emit event after updating the intent to reflect the revealed details.
    }

    // ------------------------
    // Deposit
    // ------------------------

    /**
     * @notice Deposit funds for an intent, an external state-modifying contract function.
     * @dev Pull amountIn tokens from the user into the registry.
     * @param id The intent id (uint256).
     */
    function depositIntentFunds(uint256 id) external {
        TradeIntent storage intent = intents[id];

        if (msg.sender != intent.user) revert IntentRegistry__NotIntentOwner();

        if (intent.deposited) revert IntentRegistry__AlreadyDeposited();
        intent.deposited = true;

        bool res = IERC20(intent.tokenIn).transferFrom(msg.sender, address(this), intent.amountIn);

        if (!res) {
            revert IntentRegistry__TransferInDepositIntentFailed();
        }

        emit FundsDeposited(id, intent.amountIn);
    }

    // --------------------------
    // Execute Intent
    // --------------------------

    /**
     * @notice Execute intent, an external state-modifying contract function.
     *
     * @dev Execute a revealed intent when the TWAP price condition is met.
     *
     * @param intentId The intent id (uint256).
     * @custom:signature executeIntent(uint256)
     * @custom:selector 0xc751c127
     */
    function executeIntent(uint256 intentId) external {
        TradeIntent storage intent = intents[intentId];

        if (!intent.revealed) {
            revert IntentRegistry__IntentNotRevealed();
        }

        if (intent.executed) {
            revert IntentRegistry__AlreadyExecuted();
        }

        if (block.timestamp > intent.expiry) {
            revert IntentRegistry__IntentExpired();
        }

        // Get the TWAP price from the registered Uniswap V3 pool for the token pair.
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

        if (!conditionMet) {
            revert IntentRegistry__PriceConditionNotMet();
        }

        intent.executed = true;

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

        // Leftover allowance is dangerous if the router is ever upgraded or compromised;
        // setting it back to 0 closes that window.
        IERC20(intent.tokenIn).approve(address(ROUTER), 0);
        // ---------------------------------------------------------------------

        emit IntentExecuted(intentId, currentPrice);
    }

    // --------------------------
    // Cancel Intent
    // --------------------------

    /**
     * @notice Cancel intent, an external state-modifying contract function.
     *
     * @dev lets the intent owner recover deposited funds after expiry.
     *      Rules:
     *          - Only the intent owner can cancel.
     *          - Cannot cancel an already-executed intent (funds already swapped).
     *          - Cannot cancel twice.
     *          - If funds were deposited, they are returned only after the intent has
     *            expired (prevents cancelling while a keeper could still execute).
     *          - If funds were never deposited, the intent can be cancelled at any time
     *              (no funds to return, no keeper conflict).
     *
     * @param intentId The intent id (uint256).
     * @custom:signature cancelIntent(uint256)
     * @custom:selector 0xa0a31aac
     */
    function cancelIntent(uint256 intentId) external {
        TradeIntent storage intent = intents[intentId];

        if (msg.sender != intent.user) {
            revert IntentRegistry__NotIntentOwner();
        }

        if (intent.cancelled) {
            revert IntentRegistry__AlreadyCancelled();
        }

        if (intent.executed) {
            revert IntentRegistry__IntentAlreadyExecuted();
        }

        // If funds are already sitting in this contract, wait for expiry first.
        // Pre-deposit cancellations (e.g. change of mind before deposit) are allowed anytime.
        if (intent.deposited && intent.expiry >= block.timestamp) {
            revert IntentRegistry__NotYetExpired();
        }

        intent.cancelled = true;

        if (intent.deposited) {
            bool res = IERC20(intent.tokenIn).transfer(msg.sender, intent.amountIn);
            if (!res) {
                revert IntentRegistry__CancelTransferFailed();
            }
        }

        emit IntentCancelled(intentId);
    }

    // -------------------------------------------------------------------------
    // View
    // -------------------------------------------------------------------------
    /**
     * @notice Get intent, an external view contract function.
     * @param intentId The intent id (uint256).
     * @return TradeIntent Result of getIntent.
     * @custom:signature getIntent(uint256)
     * @custom:selector 0x906e277b
     */
    function getIntent(uint256 intentId) external view returns (TradeIntent memory) {
        return intents[intentId];
    }
}
