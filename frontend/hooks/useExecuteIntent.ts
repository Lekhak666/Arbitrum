"use client";

import { useWriteContract } from "wagmi";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

export function useExecuteIntent() {
  const {
    writeContractAsync,
    isPending,
  } = useWriteContract();

  const executeIntent = async (
    intentId: bigint
  ) => {
    return await writeContractAsync({
      address:
        CONTRACTS.intentRegistry as `0x${string}`,

      abi: IntentRegistryABI,

      functionName: "executeIntent",

      args: [intentId],
    });
  };

  return {
    executeIntent,
    isPending,
  };
}