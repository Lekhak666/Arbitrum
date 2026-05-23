// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IntentRegistry} from "../../src/IntentRegistry.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";

// ─────────────────────────────────────────────────────────────────────────────
// MockERC20
// Minimal ERC-20 with a public mint so tests can fund addresses freely.
// transferFrom does NOT require a prior approve from the contract itself,
// which lets the harness pull tokens after the registry has approved it.
// ─────────────────────────────────────────────────────────────────────────────
contract MockERC20 is IERC20 {
    error MockERC20__InsufficientBalance();
    error MockERC20__InsufficientAllowance();

    string public name;
    string public symbol;
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balanceOf[msg.sender] < amount) {
            revert MockERC20__InsufficientBalance();
        }
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (balanceOf[from] < amount) revert MockERC20__InsufficientBalance();

        if (allowance[from][msg.sender] < amount) {
            revert MockERC20__InsufficientAllowance();
        }
        balanceOf[from] -= amount;
        allowance[from][msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MockRouter
// Records the last swap call so tests can assert on the exact arguments passed.
// On every swap it pulls tokenIn from the caller (the registry) and mints
// tokenOut 1-for-1 to the recipient, keeping token accounting consistent.
// ─────────────────────────────────────────────────────────────────────────────
contract MockRouter is IRouter {
    uint256 public lastAmountIn;
    uint256 public lastAmountOutMin;
    address public lastRecipient;
    address public lastPath0;
    address public lastPath1;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        lastAmountIn = amountIn;
        lastAmountOutMin = amountOutMin;
        lastRecipient = to;
        lastPath0 = path[0];
        lastPath1 = path[1];

        // Pull tokenIn from the caller (registry must have approved us).
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Mint tokenOut directly to the recipient (1-for-1 for simplicity).
        MockERC20(path[1]).mint(to, amountIn);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HarnessIntentRegistry
//
// Extends IntentRegistry with a single extra entry-point:
//   executeIntentWithMockPrice(intentId, mockPrice)
//
// This replicates every line of executeIntent except the two OracleLibrary
// calls, replacing them with a caller-supplied price.  This lets unit and fuzz
// tests exercise all execution logic (guards, CEI, approve/revoke, event) without
// needing a live Uniswap V3 pool.
//
// The real executeIntent is still present and fully tested in integration / fork
// tests (not included here); the harness does NOT override it.
// ─────────────────────────────────────────────────────────────────────────────
contract HarnessIntentRegistry is IntentRegistry {
    constructor(address _router) IntentRegistry(_router) {}

    function executeIntentWithMockPrice(uint256 intentId, uint256 mockCurrentPrice) external {
        TradeIntent storage intent = intents[intentId];

        if (!intent.revealed) revert IntentRegistry__IntentNotRevealed();
        if (intent.executed) revert IntentRegistry__AlreadyExecuted();
        if (block.timestamp > intent.expiry) {
            revert IntentRegistry__IntentExpired();
        }

        address p = tokenPairPool[intent.tokenIn][intent.tokenOut];
        if (p == address(0)) revert IntentRegistry__PoolNotRegistered();

        bool conditionMet =
            intent.greaterThan ? mockCurrentPrice >= intent.targetPrice : mockCurrentPrice <= intent.targetPrice;
        if (!conditionMet) revert IntentRegistry__PriceConditionNotMet();

        // ── CEI: mark executed before any external calls ──────────────────
        intent.executed = true;

        IERC20(intent.tokenIn).approve(address(ROUTER), intent.amountIn);

        address[] memory path = new address[](2);
        path[0] = intent.tokenIn;
        path[1] = intent.tokenOut;

        ROUTER.swapExactTokensForTokens(intent.amountIn, intent.minAmountOut, path, intent.user, block.timestamp + 300);

        // Revoke leftover allowance immediately after the swap.
        IERC20(intent.tokenIn).approve(address(ROUTER), 0);

        emit IntentExecuted(intentId, mockCurrentPrice);
    }
}
