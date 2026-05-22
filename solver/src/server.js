import express from "express";
import cors from "cors";
import { registry } from "./executor.js";

const app = express();

app.use(cors());

app.get("/intents", async (_, res) => {
  const total = await registry.nextIntentId();

  const intents = [];

  for (let i = 0; i < total; i++) {
    intents.push(await registry.intents(i));
  }

  res.json(intents);
});

app.listen(3001);
