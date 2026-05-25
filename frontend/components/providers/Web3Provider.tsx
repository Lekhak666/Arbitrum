"use client";

import { ReactNode } from "react";

import { WagmiProvider } from "wagmi";

import {
  QueryClient,
  QueryClientProvider,
} from "@tanstack/react-query";

import {
  createAppKit,
} from "@reown/appkit/react";

import {
  arbitrumSepolia,
} from "wagmi/chains";

import {
  config,
  projectId,
  wagmiAdapter,
} from "@/lib/wagmi";

const queryClient = new QueryClient();

createAppKit({
  adapters: [wagmiAdapter],

  projectId,

  metadata: {
    name: "Veil Swap",

    description:
      "Intent-based trading on Arbitrum",

    url: "http://localhost:3001",

    icons: [
      "http://localhost:3001/veilswap.png",
    ],
  },

  networks: [arbitrumSepolia],

  defaultNetwork: arbitrumSepolia,

  features: {
    analytics: false,
  },
});

export default function Web3Provider({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </WagmiProvider>
  );
}