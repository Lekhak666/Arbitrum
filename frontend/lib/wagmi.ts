"use client";

import {
  cookieStorage,
  createStorage,
} from "wagmi";

import {
  injected,
  walletConnect,
  coinbaseWallet,
} from "wagmi/connectors";

import { WagmiAdapter }
from "@reown/appkit-adapter-wagmi";

import { createAppKit }
from "@reown/appkit/react";

import {
  arbitrumSepolia,
} from "wagmi/chains";

export const projectId =
  process.env.NEXT_PUBLIC_PROJECT_ID || "";

export const networks = [
  arbitrumSepolia,
];

export const metadata = {
  name: "Veil Swap",
  description: "Intent-based trading on Arbitrum",
  url: "http://localhost:3001",
  icons: ["http://localhost:3001/veilswap.png"],
};

export const wagmiAdapter =
  new WagmiAdapter({
    storage: createStorage({
      storage: cookieStorage,
    }),

    ssr: true,

    projectId,

    networks,

    connectors: [
      injected({
        target: "metaMask",
      }),

      injected({
        target: "rabby",
      }),

      injected(),

      coinbaseWallet({
        appName: "Veil Swap",
      }),

      walletConnect({
        projectId,
      }),
    ],
  });

export const config =
  wagmiAdapter.wagmiConfig;

declare global {
  interface Window {
    appKitLoaded?: boolean;
  }
}

if (
  typeof window !== "undefined" &&
  !window.appKitLoaded
) {
  createAppKit({
    adapters: [wagmiAdapter],

    projectId,

    networks,

    metadata,

    featuredWalletIds: [],

    enableInjected: true,

    enableCoinbase: true,
  });

  window.appKitLoaded = true;
}