"use client";

import { useEffect, useState } from "react";

import {
  createPublicClient,
  http,
} from "viem";

import { arbitrumSepolia } from "viem/chains";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

const client = createPublicClient({
  chain: arbitrumSepolia,
  transport: http(),
});

export interface Intent {
  id: number;
  user: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  targetPrice: string;
  expiry: string;
  executed: boolean;
  cancelled: boolean;
}

export function useIntents() {
  const [intents, setIntents] =
    useState<Intent[]>([]);

  const [loading, setLoading] =
    useState(true);

  const fetchIntents = async () => {
    try {
      setLoading(true);

      // get latest ID
      const nextIntentId =
        await client.readContract({
          address:
            CONTRACTS.intentRegistry as `0x${string}`,

          abi: IntentRegistryABI,

          functionName:
            "nextIntentId",
        });

      const fetched: Intent[] = [];

      // fetch latest 5 intents
      for (
        let i =
          Number(nextIntentId) - 1;
        i >= 0 &&
        fetched.length < 5;
        i--
      ) {
        const intent =
          await client.readContract({
            address:
              CONTRACTS.intentRegistry as `0x${string}`,

            abi: IntentRegistryABI,

            functionName:
              "getIntent",

            args: [BigInt(i)],
          });

        fetched.push({
          id: i,

          user: intent.user,

          tokenIn:
            intent.tokenIn,

          tokenOut:
            intent.tokenOut,

          amountIn:
            intent.amountIn.toString(),

          targetPrice:
            intent.targetPrice.toString(),

          expiry:
            intent.expiry.toString(),

          executed:
            intent.executed,

          cancelled:
            intent.cancelled,
        });
      }

      setIntents(fetched);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchIntents();

    const interval =
      setInterval(fetchIntents, 10000);

    return () =>
      clearInterval(interval);
  }, []);

  return {
    intents,
    loading,
    refetch: fetchIntents,
  };
}