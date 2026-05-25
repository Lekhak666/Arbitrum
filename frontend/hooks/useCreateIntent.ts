"use client";

import { useWriteContract } from "wagmi";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

export function useCreateIntent() {
  const {
    writeContractAsync,
    isPending,
  } = useWriteContract();

  async function createIntent(
    commitmentHash: `0x${string}`,
    expiry: bigint
  ) {

    console.log(
      "CONTRACT:",
      CONTRACTS.INTENT_REGISTRY
    );

    console.log(
      "ABI:",
      IntentRegistryABI
    );

    console.log({
      commitmentHash,
      expiry,
    });

    return await writeContractAsync({
      address:
        CONTRACTS.INTENT_REGISTRY as `0x${string}`,

      abi: IntentRegistryABI,

      functionName: "createIntent",

      args: [commitmentHash, expiry],
    });
  }

  return {
    createIntent,
    isPending,
  };
}