"use client";

import { motion } from "framer-motion";

import { useIntents } from "@/hooks/useIntents";

export default function RecentIntents() {
  const {
    intents,
    loading,
  } = useIntents();

  return (
    <motion.div
      whileHover={{
        y: -4,
      }}
      className="glass rounded-[32px] p-8"
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <h2 className="text-3xl font-bold">
          Live Intents
        </h2>

        <div className="flex items-center gap-2 text-sm text-green-400">
          <div className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />

          Live
        </div>
      </div>

      {/* Loading */}
      {loading && (
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="glass rounded-2xl p-5 animate-pulse h-24"
            />
          ))}
        </div>
      )}

      {/* Intents */}
      <div className="space-y-4">
        {intents.map((intent) => (
          <motion.div
            key={intent.id}
            whileHover={{
              scale: 1.01,
            }}
            className="glass rounded-2xl p-5"
          >
            <div className="flex items-start justify-between">
              {/* Left */}
              <div>
                <h3 className="text-lg font-semibold">
                  Intent #{intent.id}
                </h3>

                <p className="text-white/60 text-sm mt-1">
                  User:
                  {" "}
                  {intent.user.slice(
                    0,
                    6
                  )}
                  ...
                  {intent.user.slice(-4)}
                </p>

                <p className="text-white/50 text-sm mt-3 break-all">
                  Token In:
                  {" "}
                  {intent.tokenIn}
                </p>

                <p className="text-white/50 text-sm break-all">
                  Token Out:
                  {" "}
                  {intent.tokenOut}
                </p>
              </div>

              {/* Status */}
              <div
                className={`px-4 py-2 rounded-full text-sm ${
                  intent.executed
                    ? "bg-green-400/15 text-green-400"
                    : intent.cancelled
                    ? "bg-red-400/15 text-red-400"
                    : "bg-yellow-400/15 text-yellow-400"
                }`}
              >
                {intent.executed
                  ? "Executed"
                  : intent.cancelled
                  ? "Cancelled"
                  : "Pending"}
              </div>
            </div>

            {/* Bottom */}
            <div className="mt-5 grid grid-cols-2 gap-4 text-sm">
              <div>
                <p className="text-white/40">
                  Amount
                </p>

                <p className="mt-1">
                  {intent.amountIn}
                </p>
              </div>

              <div>
                <p className="text-white/40">
                  Target Price
                </p>

                <p className="mt-1">
                  {intent.targetPrice}
                </p>
              </div>
            </div>
          </motion.div>
        ))}
      </div>
    </motion.div>
  );
}