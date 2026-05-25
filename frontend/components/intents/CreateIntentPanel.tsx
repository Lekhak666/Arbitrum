"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { toast } from "sonner";

import { useCreateIntent } from "@/hooks/useCreateIntent";

export default function CreateIntentPanel() {
  const { createIntent, isPending } =
    useCreateIntent();

  const [expiry, setExpiry] = useState("24");

  async function handleCreateIntent() {
    try {
      const commitmentHash =
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

      const expiryTimestamp =
        Math.floor(Date.now() / 1000) +
        Number(expiry) * 60 * 60;

      await createIntent(
        commitmentHash,
        BigInt(expiryTimestamp)
      );

      toast.success(
        "Intent submitted successfully"
      );
    } catch (err) {
      console.error(err);

      toast.error("Transaction failed");
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 40 }}
      animate={{ opacity: 1, y: 0 }}
      className="
        rounded-3xl
        border border-cyan-500/20
        bg-white/5
        backdrop-blur-xl
        p-8
        shadow-[0_0_60px_rgba(0,255,255,0.10)]
      "
    >
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-bold">
          Create Intent
        </h2>

        <div
          className="
            px-3 py-1
            rounded-full
            bg-cyan-400/10
            text-cyan-300
            text-xs
            border border-cyan-400/20
          "
        >
          ARBITRUM
        </div>
      </div>

      <div className="space-y-5">
        <div>
          <label className="text-sm text-gray-400">
            Expiry (hours)
          </label>

          <input
            value={expiry}
            onChange={(e) =>
              setExpiry(e.target.value)
            }
            placeholder="24"
            className="
              mt-2
              w-full
              rounded-xl
              bg-black/30
              border border-white/10
              px-4 py-3
              outline-none
              transition-all
              focus:border-cyan-400
            "
          />
        </div>

        <button
          onClick={handleCreateIntent}
          disabled={isPending}
          className="
            w-full
            rounded-xl
            bg-cyan-400
            text-black
            font-semibold
            py-3
            transition-all
            hover:scale-[1.02]
            disabled:opacity-50
          "
        >
          {isPending
            ? "Submitting..."
            : "Submit Intent"}
        </button>
      </div>
    </motion.div>
  );
}