"use client";

import { useWriteContract } from "wagmi";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

export function useRevealIntent() {
  const {
    writeContractAsync,
    isPending,
  } = useWriteContract();

  const revealIntent = async ({
    intentId,
    tokenIn,
    tokenOut,
    amountIn,
    targetPrice,
    minAmountOut,
    greaterThan,
    secret,
  }: {
    intentId: bigint;
    tokenIn: `0x${string}`;
    tokenOut: `0x${string}`;
    amountIn: bigint;
    targetPrice: bigint;
    minAmountOut: bigint;
    greaterThan: boolean;
    secret: `0x${string}`;
  }) => {
    return await writeContractAsync({
      address:
        CONTRACTS.intentRegistry as `0x${string}`,

      abi: IntentRegistryABI,

      functionName: "revealIntent",

      args: [
        intentId,
        tokenIn,
        tokenOut,
        amountIn,
        targetPrice,
        minAmountOut,
        greaterThan,
        secret,
      ],
    });
  };

  return {
    revealIntent,
    isPending,
  };
}