// src/api/routes.ts
import { Router, Request, Response } from "express";
import { z } from "zod";
import { prisma } from "../db/client";
import { deriveStatus, type IntentResponse } from "../types";
import { logger } from "../utils/logger";

export const router = Router();

// ── Helper: map a Prisma Intent row → API response shape ─────────────────────
function toResponse(intent: any): IntentResponse {
  return {
    intentId: intent.intentId.toString(),
    user: intent.user,
    status: deriveStatus({
      revealed: intent.revealed,
      deposited: intent.deposited,
      executed: intent.executed,
      cancelled: intent.cancelled,
      expiry: intent.expiry,
    }),
    expiry: intent.expiry.toString(),
    tokenIn: intent.tokenIn,
    tokenOut: intent.tokenOut,
    amountIn: intent.amountIn,
    targetPrice: intent.targetPrice,
    minAmountOut: intent.minAmountOut,
    greaterThan: intent.greaterThan,
    revealed: intent.revealed,
    deposited: intent.deposited,
    executed: intent.executed,
    cancelled: intent.cancelled,
    txHash: intent.txHash,
    executedTxHash: intent.executedTxHash,
    cancelledTxHash: intent.cancelledTxHash,
    twapPriceAtExec: intent.twapPriceAtExec,
    createdAt: intent.createdAt.toISOString(),
    updatedAt: intent.updatedAt.toISOString(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GET /intents
// Query params:
//   user     — filter by wallet address (lowercase)
//   status   — filter by derived status
//   page     — pagination (default 1)
//   limit    — results per page (default 20, max 100)
// ─────────────────────────────────────────────────────────────────────────────
const listQuerySchema = z.object({
  user: z.string().toLowerCase().optional(),
  status: z
    .enum([
      "SUBMITTED",
      "REVEALED",
      "READY",
      "EXECUTED",
      "CANCELLED",
      "EXPIRED",
    ])
    .optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
});

router.get("/intents", async (req: Request, res: Response) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const { user, status, page, limit } = parsed.data;
  const skip = (page - 1) * limit;
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000));

  // Build the where clause.
  const where: any = {};
  if (user) where.user = user;

  if (status) {
    switch (status) {
      case "SUBMITTED":
        where.revealed = false;
        where.executed = false;
        where.cancelled = false;
        break;
      case "REVEALED":
        where.revealed = true;
        where.deposited = false;
        where.executed = false;
        where.cancelled = false;
        break;
      case "READY":
        where.revealed = true;
        where.deposited = true;
        where.executed = false;
        where.cancelled = false;
        where.expiry = { gte: nowSeconds };
        break;
      case "EXECUTED":
        where.executed = true;
        break;
      case "CANCELLED":
        where.cancelled = true;
        break;
      case "EXPIRED":
        where.executed = false;
        where.cancelled = false;
        where.expiry = { lt: nowSeconds };
        break;
    }
  }

  try {
    const [intents, total] = await Promise.all([
      prisma.intent.findMany({
        where,
        skip,
        take: limit,
        orderBy: { intentId: "desc" },
      }),
      prisma.intent.count({ where }),
    ]);

    return res.json({
      data: intents.map(toResponse),
      meta: { total, page, limit, pages: Math.ceil(total / limit) },
    });
  } catch (err) {
    logger.error("GET /intents error", { err });
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /intents/:intentId
// ─────────────────────────────────────────────────────────────────────────────
router.get("/intents/:intentId", async (req: Request, res: Response) => {
  const id = BigInt(req.params.intentId);

  try {
    const intent = await prisma.intent.findUnique({ where: { intentId: id } });
    if (!intent) return res.status(404).json({ error: "Intent not found" });
    return res.json(toResponse(intent));
  } catch (err) {
    logger.error("GET /intents/:id error", { err });
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /users/:address/intents
// Convenience endpoint — returns all intents for a specific wallet.
// ─────────────────────────────────────────────────────────────────────────────
router.get("/users/:address/intents", async (req: Request, res: Response) => {
  const address = req.params.address.toLowerCase();
  const page = Number(req.query.page ?? 1);
  const limit = Math.min(Number(req.query.limit ?? 20), 100);
  const skip = (page - 1) * limit;

  try {
    const [intents, total] = await Promise.all([
      prisma.intent.findMany({
        where: { user: address },
        skip,
        take: limit,
        orderBy: { intentId: "desc" },
      }),
      prisma.intent.count({ where: { user: address } }),
    ]);

    return res.json({
      data: intents.map(toResponse),
      meta: { total, page, limit, pages: Math.ceil(total / limit) },
    });
  } catch (err) {
    logger.error("GET /users/:address/intents error", { err });
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /stats
// High-level counts useful for a dashboard.
// ─────────────────────────────────────────────────────────────────────────────
router.get("/stats", async (_req: Request, res: Response) => {
  const nowSeconds = BigInt(Math.floor(Date.now() / 1000));

  try {
    const [total, executed, cancelled, ready, expired] = await Promise.all([
      prisma.intent.count(),
      prisma.intent.count({ where: { executed: true } }),
      prisma.intent.count({ where: { cancelled: true } }),
      prisma.intent.count({
        where: {
          revealed: true,
          deposited: true,
          executed: false,
          cancelled: false,
          expiry: { gte: nowSeconds },
        },
      }),
      prisma.intent.count({
        where: {
          executed: false,
          cancelled: false,
          expiry: { lt: nowSeconds },
        },
      }),
    ]);

    return res.json({ total, executed, cancelled, ready, expired });
  } catch (err) {
    logger.error("GET /stats error", { err });
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /health  — liveness probe
// ─────────────────────────────────────────────────────────────────────────────
router.get("/health", (_req: Request, res: Response) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});
