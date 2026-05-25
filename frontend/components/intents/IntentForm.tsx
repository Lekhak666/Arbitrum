"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { toast } from "sonner";

import { useCreateIntent } from "@/hooks/useCreateIntent";

export default function IntentForm() {
  const { createIntent, isPending } = useCreateIntent();

  const [expiry, setExpiry] = useState("24");

  async function handleSubmit() {
    try {
      const secret =
        "0x1234567890123456789012345678901234567890123456789012345678901234";

      const commitmentHash =
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

      const expiryTimestamp =
        Math.floor(Date.now() / 1000) +
        Number(expiry) * 60 * 60;

      await createIntent(
        commitmentHash,
        BigInt(expiryTimestamp)
      );

      toast.success("Intent Submitted");
    } catch (err) {
      console.error(err);
      toast.error("Transaction Failed");
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
        shadow-[0_0_60px_rgba(0,255,255,0.12)]
      "
    >
      <h2 className="text-2xl font-bold mb-6">
        Create Intent
      </h2>

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
            className="
              mt-2
              w-full
              rounded-xl
              bg-black/30
              border border-white/10
              px-4 py-3
              outline-none
              focus:border-cyan-400
            "
          />
        </div>

        <button
          onClick={handleSubmit}
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