// src/api/app.ts
import express from "express";
import cors from "cors";
import { router } from "./routes";
import { logger } from "../utils/logger";

export function createApp() {
  const app = express();

  app.use(cors({ origin: process.env.API_CORS_ORIGIN ?? "*" }));
  app.use(express.json());

  // Request logger
  app.use((req, _res, next) => {
    logger.debug(`${req.method} ${req.path}`, { query: req.query });
    next();
  });

  app.use("/api/v1", router);

  // 404 fallback
  app.use((_req, res) => {
    res.status(404).json({ error: "Not found" });
  });

  return app;
}
