import { registry, execute } from "./executor.js";
import { getPrice } from "./oracle.js";

const activeIntents = new Set();

async function monitorIntent(id) {
  if (activeIntents.has(id)) return;

  activeIntents.add(id);

  console.log(`Monitoring intent ${id}`);

  const interval = setInterval(async () => {
    try {
      const intent = await registry.intents(id);

      if (!intent.revealed || intent.executed) {
        clearInterval(interval);
        activeIntents.delete(id);
        return;
      }

      const price = await getPrice();

      console.log(`Intent ${id} | Price: ${price}`);

      const target = Number(intent.targetPrice);

      const gt = intent.greaterThan;

      const shouldExecute = gt ? price > target : price < target;

      if (shouldExecute) {
        await execute(id, price);

        clearInterval(interval);
        activeIntents.delete(id);
      }
    } catch (err) {
      console.error(`Intent ${id}:`, err.shortMessage || err.message);
    }
  }, 5000);
}

export async function watch() {
  console.log("Solver watching...");

  const total = await registry.nextIntentId();

  for (let i = 0; i < total; i++) {
    await monitorIntent(i);
  }

  registry.on("IntentSubmitted", async (id) => {
    console.log(`New intent ${id}`);

    await monitorIntent(Number(id));
  });
}
