-- CreateTable
CREATE TABLE "Intent" (
    "intentId" BIGINT NOT NULL,
    "user" TEXT NOT NULL,
    "commitmentHash" TEXT NOT NULL,
    "expiry" BIGINT NOT NULL,
    "blockNumber" BIGINT NOT NULL,
    "txHash" TEXT NOT NULL,
    "tokenIn" TEXT,
    "tokenOut" TEXT,
    "amountIn" TEXT,
    "targetPrice" TEXT,
    "minAmountOut" TEXT,
    "greaterThan" BOOLEAN,
    "revealed" BOOLEAN NOT NULL DEFAULT false,
    "deposited" BOOLEAN NOT NULL DEFAULT false,
    "executed" BOOLEAN NOT NULL DEFAULT false,
    "cancelled" BOOLEAN NOT NULL DEFAULT false,
    "executedTxHash" TEXT,
    "executedBlock" BIGINT,
    "twapPriceAtExec" TEXT,
    "cancelledTxHash" TEXT,
    "cancelledBlock" BIGINT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Intent_pkey" PRIMARY KEY ("intentId")
);

-- CreateTable
CREATE TABLE "IndexerState" (
    "id" INTEGER NOT NULL DEFAULT 1,
    "lastIndexedBlock" BIGINT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IndexerState_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Intent_user_idx" ON "Intent"("user");

-- CreateIndex
CREATE INDEX "Intent_revealed_executed_cancelled_expiry_idx" ON "Intent"("revealed", "executed", "cancelled", "expiry");
