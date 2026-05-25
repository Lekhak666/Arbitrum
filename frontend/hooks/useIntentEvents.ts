"use client";

import { useEffect, useState } from "react";
import { publicClient } from "@/lib/publicClient";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

export interface IntentEvent {
  type: string;
  intentId: string;
  txHash?: string;
}

export function useIntentEvents() {
  const [events, setEvents] = useState<
    IntentEvent[]
  >([]);

  useEffect(() => {
    const unwatchSubmitted =
      publicClient.watchContractEvent({
        address:
          CONTRACTS.INTENT_REGISTRY as `0x${string}`,

        abi: IntentRegistryABI,

        eventName: "IntentSubmitted",

        onLogs(logs) {
          logs.forEach((log: any) => {
            setEvents((prev) => [
              {
                type: "Intent Submitted",
                intentId:
                  log.args.intentId?.toString(),

                txHash:
                  log.transactionHash,
              },
              ...prev,
            ]);
          });
        },
      });

    const unwatchExecuted =
      publicClient.watchContractEvent({
        address:
          CONTRACTS.INTENT_REGISTRY as `0x${string}`,

        abi: IntentRegistryABI,

        eventName: "IntentExecuted",

        onLogs(logs) {
          logs.forEach((log: any) => {
            setEvents((prev) => [
              {
                type: "Intent Executed",
                intentId:
                  log.args.intentId?.toString(),

                txHash:
                  log.transactionHash,
              },
              ...prev,
            ]);
          });
        },
      });

    return () => {
      unwatchSubmitted?.();
      unwatchExecuted?.();
    };
  }, []);

  return {
    events,
  };
}
