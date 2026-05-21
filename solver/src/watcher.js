import { getPrice } from "./oracle.js";

import { execute } from "./executor.js";

export const watch = async () => {
  while (true) {
    const price = await getPrice();

    console.log("Price:", price);

    if (price >= 4200) {
      await execute(0, price);

      break;
    }

    await new Promise((r) => setTimeout(r, 5000));
  }
};

export default {
  watch,
};
