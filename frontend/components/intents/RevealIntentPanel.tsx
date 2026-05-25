"use client";

import { useState } from "react";

import { motion } from "framer-motion";

import { toast } from "sonner";

import { stringToHex } from "viem";

import { useRevealIntent } from "@/hooks/useRevealIntent";

export default function RevealIntentPanel() {
  const {
    revealIntent,
    isPending,
  } = useRevealIntent();

  const [intentId, setIntentId] =
    useState("");

  const handleReveal = async () => {
    try {
      const saved =
        localStorage.getItem(
          "latestIntent"
        );

      if (!saved) {
        toast.error(
          "No local intent found"
        );

        return;
      }

      const parsed =
        JSON.parse(saved);

      toast.loading(
        "Revealing intent..."
      );

      const tx =
        await revealIntent({
          intentId: BigInt(intentId),

          tokenIn:
            parsed.tokenIn,

          tokenOut:
            parsed.tokenOut,

          amountIn: BigInt(
            Number(parsed.amount) *
              1e18
          ),

          targetPrice:
            BigInt(
              parsed.targetPrice
            ),

          minAmountOut: BigInt(0),

          greaterThan: true,

          secret: stringToHex(
            parsed.secret,
            {
              size: 32,
            }
          ),
        });

      toast.dismiss();

      toast.success(
        "Intent revealed!"
      );

      console.log(tx);
    } catch (err) {
      console.error(err);

      toast.dismiss();

      toast.error(
        "Reveal failed"
      );
    }
  };

  return (
    <motion.div
      whileHover={{
        y: -4,
      }}
      className="glass rounded-[32px] p-8 mt-6"
    >
      <h2 className="text-3xl font-bold mb-6">
        Reveal Intent
      </h2>

      <input
        placeholder="Intent ID"
        value={intentId}
        onChange={(e) =>
          setIntentId(
            e.target.value
          )
        }
        className="w-full glass rounded-2xl px-5 py-4 bg-transparent outline-none"
      />

      <button
        disabled={isPending}
        onClick={handleReveal}
        className="mt-6 w-full rounded-2xl py-4 bg-gradient-to-r from-purple-400 to-cyan-400 text-black font-bold disabled:opacity-50"
      >
        {isPending
          ? "Revealing..."
          : "Reveal Intent"}
      </button>
    </motion.div>
  );
}