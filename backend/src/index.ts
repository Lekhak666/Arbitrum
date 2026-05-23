// src/index.ts
import "dotenv/config";
import { createApp } from "./api/app.ts";
import { startIndexer } from "./indexer/indexer.ts";
import { startKeeper } from "./keeper/keeper.ts";
import { prisma } from "./db/client.ts";
import { logger } from "./utils/logger.ts";

const PORT = Number(process.env.API_PORT ?? 3001);

async function main() {
  logger.info("Booting IntentRegistry backend...");

  // Verify DB connection.
  await prisma.$connect();
  logger.info("Database connected");

  // Start the event indexer (runs in background via setInterval).
  await startIndexer();

  // Start the keeper bot (runs in background via setInterval).
  await startKeeper();

  // Start the REST API.
  const app = createApp();
  app.listen(PORT, () => {
    logger.info(`API listening on http://localhost:${PORT}`);
  });
}

main().catch((err) => {
  logger.error("Fatal startup error", { err });
  process.exit(1);
});

// Graceful shutdown
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);

async function shutdown() {
  logger.info("Shutting down...");
  await prisma.$disconnect();
  process.exit(0);
}
