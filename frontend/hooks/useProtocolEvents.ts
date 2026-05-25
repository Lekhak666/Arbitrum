"use client";

import { useEffect, useState } from "react";

import {
  createPublicClient,
  http,
} from "viem";

import { arbitrumSepolia } from "viem/chains";

import IntentRegistryABI from "@/lib/abi/IntentRegistry.json";

import { CONTRACTS } from "@/lib/contracts";

export interface ProtocolEvent {
  id: string;

  type:
    | "submitted"
    | "revealed"
    | "executed";

  intentId: string;

  txHash: string;

  timestamp: number;
}

export function useProtocolEvents() {
  const [events, setEvents] =
    useState<ProtocolEvent[]>([]);

  useEffect(() => {
    const client =
      createPublicClient({
        chain: arbitrumSepolia,

        transport: http(),
      });

    // Intent Submitted
    const unwatchSubmitted =
      client.watchContractEvent({
        address:
          CONTRACTS.intentRegistry as `0x${string}`,

        abi: IntentRegistryABI,

        eventName:
          "IntentSubmitted",

        onLogs(logs) {
          logs.forEach((log) => {
            const intentId =
              String(
                log.args.intentId
              );

            setEvents((prev) => [
              {
                id:
                  crypto.randomUUID(),

                type: "submitted",

                intentId,

                txHash:
                  log.transactionHash,

                timestamp:
                  Date.now(),
              },

              ...prev,
            ]);
          });
        },
      });

    // Intent Revealed
    const unwatchReveal =
      client.watchContractEvent({
        address:
          CONTRACTS.intentRegistry as `0x${string}`,

        abi: IntentRegistryABI,

        eventName:
          "IntentRevealed",

        onLogs(logs) {
          logs.forEach((log) => {
            const intentId =
              String(
                log.args.intentId
              );

            setEvents((prev) => [
              {
                id:
                  crypto.randomUUID(),

                type: "revealed",

                intentId,

                txHash:
                  log.transactionHash,

                timestamp:
                  Date.now(),
              },

              ...prev,
            ]);
          });
        },
      });

    // Intent Executed
    const unwatchExecuted =
      client.watchContractEvent({
        address:
          CONTRACTS.intentRegistry as `0x${string}`,

        abi: IntentRegistryABI,

        eventName:
          "IntentExecuted",

        onLogs(logs) {
          logs.forEach((log) => {
            const intentId =
              String(
                log.args.intentId
              );

            setEvents((prev) => [
              {
                id:
                  crypto.randomUUID(),

                type: "executed",

                intentId,

                txHash:
                  log.transactionHash,

                timestamp:
                  Date.now(),
              },

              ...prev,
            ]);
          });
        },
      });

    return () => {
      unwatchSubmitted();

      unwatchReveal();

      unwatchExecuted();
    };
  }, []);

  return events;
}