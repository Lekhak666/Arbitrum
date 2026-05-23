// src/utils/client.ts
import { createPublicClient, createWalletClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrum } from "viem/chains";

// ── ABI: only the events and functions the backend needs ─────────────────────
export const INTENT_REGISTRY_ABI = parseAbi([
  // Events
  "event IntentSubmitted(uint256 indexed intentId, address indexed user)",
  "event IntentRevealed(uint256 indexed intentId)",
  "event FundsDeposited(uint256 indexed id, uint256 amount)",
  "event IntentExecuted(uint256 indexed intentId, uint256 twapPrice)",
  "event IntentCancelled(uint256 indexed intentId)",

  // Read
  "function getIntent(uint256 intentId) view returns ((address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 targetPrice, uint256 minAmountOut, bool greaterThan, uint256 expiry, bytes32 commitmentHash, bool revealed, bool executed, bool deposited, bool cancelled))",
  "function nextIntentId() view returns (uint256)",

  // Write (keeper calls this)
  "function executeIntent(uint256 intentId)",
]);

// ── Public client — used by the indexer and keeper to read chain state ────────
export const publicClient = createPublicClient({
  chain: arbitrum,
  transport: http(process.env.RPC_URL!),
});

// ── Wallet client — used by the keeper to send executeIntent transactions ─────
export function createKeeperClient() {
  const account = privateKeyToAccount(
    process.env.KEEPER_PRIVATE_KEY! as `0x${string}`,
  );
  return createWalletClient({
    account,
    chain: arbitrum,
    transport: http(process.env.RPC_URL!),
  });
}

export const CONTRACT_ADDRESS = process.env
  .INTENT_REGISTRY_ADDRESS! as `0x${string}`;
