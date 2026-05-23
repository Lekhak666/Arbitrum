// src/types/index.ts

// ── Intent status (derived from the four boolean flags) ──────────────────────
export type IntentStatus =
  | "SUBMITTED" // submitted, not yet revealed
  | "REVEALED" // revealed, not yet deposited
  | "READY" // revealed + deposited, waiting for price condition
  | "EXECUTED" // swap has gone through
  | "CANCELLED" // cancelled by user
  | "EXPIRED"; // past expiry, not executed or cancelled

export function deriveStatus(intent: {
  revealed: boolean;
  deposited: boolean;
  executed: boolean;
  cancelled: boolean;
  expiry: bigint;
}): IntentStatus {
  if (intent.executed) return "EXECUTED";
  if (intent.cancelled) return "CANCELLED";

  const now = BigInt(Math.floor(Date.now() / 1000));
  if (intent.expiry < now) return "EXPIRED";

  if (intent.revealed && intent.deposited) return "READY";
  if (intent.revealed) return "REVEALED";
  return "SUBMITTED";
}

// ── API response shape ────────────────────────────────────────────────────────
export interface IntentResponse {
  intentId: string;
  user: string;
  status: IntentStatus;
  expiry: string;
  tokenIn: string | null;
  tokenOut: string | null;
  amountIn: string | null;
  targetPrice: string | null;
  minAmountOut: string | null;
  greaterThan: boolean | null;
  revealed: boolean;
  deposited: boolean;
  executed: boolean;
  cancelled: boolean;
  txHash: string;
  executedTxHash: string | null;
  cancelledTxHash: string | null;
  twapPriceAtExec: string | null;
  createdAt: string;
  updatedAt: string;
}
