// src/keeper/keeper.ts
//
// Every KEEPER_POLL_INTERVAL_MS the keeper:
//   1. Queries the DB for all READY intents (revealed + deposited + not expired)
//   2. For each intent, calls getIntent on-chain to confirm current state
//   3. Calls executeIntent — the contract will revert if the TWAP condition
//      is not yet met, so the keeper just catches that revert and moves on
//   4. Marks the intent as executed in the DB on success
//
// The contract enforces all conditions (price, expiry, double-execution) so
// the keeper does NOT need to replicate that logic — it just fires and lets
// the contract decide.

import { prisma } from "../db/client";
import {
  publicClient,
  createKeeperClient,
  CONTRACT_ADDRESS,
  INTENT_REGISTRY_ABI,
} from "../utils/client";
import { logger } from "../utils/logger";
import { parseGwei } from "viem";

const POLL_MS = Number(process.env.KEEPER_POLL_INTERVAL_MS ?? "15000");
const MAX_GAS_GWEI = BigInt(process.env.KEEPER_MAX_GAS_GWEI ?? "50");

// ─────────────────────────────────────────────────────────────────────────────
// Attempt to execute a single intent.
// Returns true if the tx was sent, false if it was skipped (price not met or
// already handled).
// ─────────────────────────────────────────────────────────────────────────────
async function tryExecute(intentId: bigint): Promise<boolean> {
  const keeper = createKeeperClient();

  // Guard: skip if gas is too high to avoid burning keeper funds.
  const gasPrice = await publicClient.getGasPrice();
  if (gasPrice > parseGwei(MAX_GAS_GWEI.toString())) {
    logger.warn("Gas price too high, skipping", {
      gasPriceGwei: (gasPrice / 10n ** 9n).toString(),
      maxGwei: MAX_GAS_GWEI.toString(),
    });
    return false;
  }

  // Simulate first — this will revert with IntentRegistry__PriceConditionNotMet
  // if the TWAP condition is not yet met, saving the keeper gas.
  try {
    await publicClient.simulateContract({
      address: CONTRACT_ADDRESS,
      abi: INTENT_REGISTRY_ABI,
      functionName: "executeIntent",
      args: [intentId],
      account: keeper.account,
    });
  } catch (simErr: any) {
    // Price condition not met — not an error, just not time yet.
    if (simErr?.message?.includes("PriceConditionNotMet")) {
      logger.debug("Price condition not met, skipping", {
        intentId: intentId.toString(),
      });
      return false;
    }
    // Intent already executed / expired / cancelled on-chain.
    if (
      simErr?.message?.includes("AlreadyExecuted") ||
      simErr?.message?.includes("IntentExpired") ||
      simErr?.message?.includes("AlreadyCancelled")
    ) {
      logger.info("Intent no longer actionable on-chain, syncing DB", {
        intentId: intentId.toString(),
      });
      // Re-read on-chain state and patch the DB.
      await syncIntentFromChain(intentId);
      return false;
    }
    logger.error("Unexpected simulate error", {
      intentId: intentId.toString(),
      err: simErr?.message,
    });
    return false;
  }

  // Simulation passed — send the real transaction.
  try {
    const hash = await keeper.writeContract({
      address: CONTRACT_ADDRESS,
      abi: INTENT_REGISTRY_ABI,
      functionName: "executeIntent",
      args: [intentId],
    });

    logger.info("executeIntent tx sent", {
      intentId: intentId.toString(),
      txHash: hash,
    });

    // Wait for confirmation.
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    if (receipt.status === "success") {
      logger.info("Intent executed successfully", {
        intentId: intentId.toString(),
        txHash: hash,
        blockNumber: receipt.blockNumber.toString(),
      });

      // The indexer will pick up the IntentExecuted event and update the DB
      // on its next cycle, but we optimistically update here too so the API
      // reflects the change immediately.
      await prisma.intent.update({
        where: { intentId },
        data: {
          executed: true,
          executedTxHash: hash,
          executedBlock: receipt.blockNumber,
        },
      });

      return true;
    } else {
      logger.error("executeIntent tx reverted", {
        intentId: intentId.toString(),
        txHash: hash,
      });
      return false;
    }
  } catch (err: any) {
    logger.error("Failed to send executeIntent tx", {
      intentId: intentId.toString(),
      err: err?.message,
    });
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Re-read on-chain state and sync the DB (used when the keeper detects a
// state mismatch — e.g. intent was cancelled directly on-chain).
// ─────────────────────────────────────────────────────────────────────────────
async function syncIntentFromChain(intentId: bigint): Promise<void> {
  const onChain = await publicClient.readContract({
    address: CONTRACT_ADDRESS,
    abi: INTENT_REGISTRY_ABI,
    functionName: "getIntent",
    args: [intentId],
  });

  await prisma.intent.update({
    where: { intentId },
    data: {
      executed: onChain.executed,
      cancelled: onChain.cancelled,
      deposited: onChain.deposited,
      revealed: onChain.revealed,
    },
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// One keeper cycle
// ─────────────────────────────────────────────────────────────────────────────
async function runKeeperCycle(): Promise<void> {
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000));

  // Find all intents that are revealed, deposited, not yet executed/cancelled,
  // and not expired.
  const candidates = await prisma.intent.findMany({
    where: {
      revealed: true,
      deposited: true,
      executed: false,
      cancelled: false,
      expiry: { gt: nowSeconds },
    },
    orderBy: { expiry: "asc" }, // prioritise intents closest to expiry
  });

  if (candidates.length === 0) {
    logger.debug("Keeper: no actionable intents");
    return;
  }

  logger.info(`Keeper: checking ${candidates.length} candidate intents`);

  // Execute candidates sequentially to avoid nonce collisions on the keeper wallet.
  let executedCount = 0;
  for (const intent of candidates) {
    const executed = await tryExecute(intent.intentId);
    if (executed) executedCount++;
  }

  if (executedCount > 0) {
    logger.info(`Keeper cycle complete`, {
      executed: executedCount,
      checked: candidates.length,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public: start the keeper polling loop
// ─────────────────────────────────────────────────────────────────────────────
export async function startKeeper(): Promise<void> {
  if (!process.env.KEEPER_PRIVATE_KEY) {
    logger.warn("KEEPER_PRIVATE_KEY not set — keeper bot disabled");
    return;
  }

  logger.info("Starting keeper bot...", { pollIntervalMs: POLL_MS });

  // Run once immediately, then on interval.
  await runKeeperCycle();
  setInterval(runKeeperCycle, POLL_MS);
}
