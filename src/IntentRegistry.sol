// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    error IntentRegistry__ExpiryPassed();
    error IntentRegistry__NotIntentOwner();
    error IntentRegistry__AlreadyRevealed();
    error IntentRegistry__RevealHashMismatch();
    error IntentRegistry__IntentNotRevealed();
    error IntentRegistry__AlreadyExecuted();
    error IntentRegistry__IntentExpired();
    error IntentRegistry__PriceConditionNotMet();

    uint256 public nextIntentId;

    struct TradeIntent {
        address user; // Owner of the intent
        address tokenIn; // Token the user wants to sell
        address tokenOut; // Token the user wants to buy
        uint256 amountIn; // Amount of tokenIn the user wants to sell
        uint256 targetPrice; // Target price for the trade (e.g., price of tokenIn in terms of tokenOut)
        bool greaterThan; // If true, execute when current price >= targetPrice; if false, execute when current price <= targetPrice
        uint256 expiry; // Timestamp after which the intent can no longer be executed : HIDDEN ORDER HASH
        bytes32 commitmentHash; // Hash of the intent details for the commit-reveal scheme
        bool revealed; // Whether the intent has been revealed
        bool executed; // Whether the intent has been executed
    }

    mapping(uint256 intentId => TradeIntent) public intents; // Mapping from intent ID to TradeIntent

    event IntentSubmitted(uint256 indexed intentId, address indexed user); // Emitted when a new intent is submitted

    event IntentRevealed(uint256 indexed intentId); // Emitted when an intent is revealed

    event IntentExecuted(uint256 indexed intentId, uint256 executionPrice); // Emitted when an intent is executed

    // --------------------------
    // Submit Commitment
    // --------------------------

    /**
     * @notice Submit intent, an external state-modifying contract function.
     * @param _commitmentHash The commitment hash (bytes32).
     * @param _expiry The expiry (uint256).
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
            greaterThan: true,
            expiry: _expiry,
            commitmentHash: _commitmentHash,
            revealed: false,
            executed: false
        });

        emit IntentSubmitted(nextIntentId, msg.sender);

        nextIntentId++;
    }

    // --------------------------
    // Reveal Intent
    // --------------------------

    /**
     * @notice Reveal intent, an external state-modifying contract function.
     * @param intentId The intent id (uint256).
     * @param tokenIn The token in address.
     * @param tokenOut The token out address.
     * @param amountIn The amount in (uint256).
     * @param targetPrice The target price (uint256).
     * @param greaterThan The greater than (bool).
     * @param secret The secret (bytes32).
     * @custom:signature revealIntent(uint256,address,address,uint256,uint256,bool,bytes32)
     * @custom:selector 0xaad8f8b4
     */
    function revealIntent(
        uint256 intentId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 targetPrice,
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

        bytes32 computedHash = keccak256(
            abi.encode(msg.sender, tokenIn, tokenOut, amountIn, targetPrice, greaterThan, intent.expiry, secret)
        ); // Recompute the hash using the provided details and the original expiry from storage

        if (computedHash != intent.commitmentHash) {
            revert IntentRegistry__RevealHashMismatch();
        }

        intent.tokenIn = tokenIn;
        intent.tokenOut = tokenOut;
        intent.amountIn = amountIn;
        intent.targetPrice = targetPrice;
        intent.greaterThan = greaterThan;

        intent.revealed = true;

        emit IntentRevealed(intentId); // Emit event after updating the intent to reflect the revealed details.
    }

    // --------------------------
    // Execute Intent
    // --------------------------

    /**
     * @notice Execute intent, an external state-modifying contract function.
     * @param intentId The intent id (uint256).
     * @param currentPrice The current price (uint256).
     * @custom:signature executeIntent(uint256,uint256)
     * @custom:selector 0xc751c127
     */
    function executeIntent(uint256 intentId, uint256 currentPrice) external {
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

        bool conditionMet = intent.greaterThan ? currentPrice >= intent.targetPrice : currentPrice <= intent.targetPrice;

        if (!conditionMet) {
            revert IntentRegistry__PriceConditionNotMet();
        }

        // Real version:
        // route swap through DEX

        intent.executed = true;

        emit IntentExecuted(intentId, currentPrice);
    }

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
