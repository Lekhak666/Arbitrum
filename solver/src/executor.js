import { ethers } from "ethers";

import { RPC_URL, REGISTRY } from "./config.js";

import { getWallet } from "./wallet.js";

import abi from "../abi.json" with { type: "json" };

export const execute = async (intentId, price) => {
  const provider = new ethers.JsonRpcProvider(RPC_URL);

  const wallet = getWallet(provider);

  const registry = new ethers.Contract(REGISTRY, abi, wallet);

  const tx = await registry.executeIntent(intentId, price);

  await tx.wait();

  console.log(`Executed intent ${intentId}`);
};

export default {
  execute,
};
