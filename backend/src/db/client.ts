import { PrismaClient, Prisma } from "@prisma/client";
import { logger } from "../utils/logger";

type PrismaLogEvent = { message: string; timestamp: Date; target: string };

export const prisma = new PrismaClient({
  log: [
    { emit: "event", level: "error" },
    { emit: "event", level: "warn" },
  ],
});

prisma.$on("error", (e: PrismaLogEvent) =>
  logger.error("Prisma error", { message: e.message }),
);
prisma.$on("warn", (e: PrismaLogEvent) =>
  logger.warn("Prisma warning", { message: e.message }),
);
