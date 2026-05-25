"use client";

import { motion } from "framer-motion";

import { useIntentEvents } from "@/hooks/useIntentEvents";

export default function EventFeed() {
  const { events } = useIntentEvents();

  return (
    <div
      className="
        rounded-3xl
        border border-white/10
        bg-white/5
        backdrop-blur-xl
        p-8
      "
    >
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-2xl font-bold">
          Live Event Feed
        </h2>

        <div
          className="
            flex items-center gap-2
            text-cyan-400
            text-sm
          "
        >
          <div className="w-2 h-2 rounded-full bg-cyan-400 animate-pulse" />

          LIVE
        </div>
      </div>

      <div className="space-y-4">
        {events.length === 0 && (
          <div className="text-gray-500 text-sm">
            Waiting for contract events...
          </div>
        )}

        {events.map((event, index) => (
          <motion.div
            key={index}
            initial={{
              opacity: 0,
              y: 20,
            }}
            animate={{
              opacity: 1,
              y: 0,
            }}
            className="
              rounded-2xl
              border border-cyan-500/10
              bg-black/30
              p-5
            "
          >
            <div className="flex justify-between">
              <div>
                <div className="font-semibold">
                  {event.type}
                </div>

                <div className="text-sm text-gray-400 mt-1">
                  Intent ID:
                  {" "}
                  {event.intentId}
                </div>
              </div>

              <div className="text-cyan-400 text-sm">
                LIVE
              </div>
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}