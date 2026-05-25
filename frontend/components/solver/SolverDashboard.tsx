"use client";

import { motion } from "framer-motion";

import { toast } from "sonner";

import {
  IconBolt,
  IconRobot,
  IconCpu,
} from "@tabler/icons-react";

import { useIntents } from "@/hooks/useIntents";

import { useExecuteIntent } from "@/hooks/useExecuteIntent";

export default function SolverDashboard() {
  const {
    intents,
    loading,
  } = useIntents();

  const {
    executeIntent,
    isPending,
  } = useExecuteIntent();

  const handleExecute =
    async (id: number) => {
      try {
        toast.loading(
          "Executing intent..."
        );

        const tx =
          await executeIntent(
            BigInt(id)
          );

        toast.dismiss();

        toast.success(
          "Intent executed!"
        );

        console.log(tx);
      } catch (err) {
        console.error(err);

        toast.dismiss();

        toast.error(
          "Execution failed"
        );
      }
    };

  const executableIntents =
    intents.filter(
      (intent) =>
        !intent.executed &&
        !intent.cancelled
    );

  return (
    <motion.div
      initial={{
        opacity: 0,
        y: 20,
      }}
      animate={{
        opacity: 1,
        y: 0,
      }}
      className="glass rounded-[32px] p-8"
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <div className="flex items-center gap-3">
            <IconRobot
              size={34}
              className="text-cyan-400"
            />

            <h2 className="text-3xl font-bold">
              Solver Network
            </h2>
          </div>

          <p className="text-white/50 mt-2">
            Autonomous execution engine
          </p>
        </div>

        <div className="glass px-5 py-3 rounded-2xl">
          <div className="flex items-center gap-2 text-green-400">
            <div className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />

            Online
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="glass rounded-2xl p-5">
          <p className="text-white/50 text-sm">
            Active Solvers
          </p>

          <h3 className="text-3xl font-bold mt-2">
            12
          </h3>
        </div>

        <div className="glass rounded-2xl p-5">
          <p className="text-white/50 text-sm">
            Executable
          </p>

          <h3 className="text-3xl font-bold mt-2">
            {
              executableIntents.length
            }
          </h3>
        </div>

        <div className="glass rounded-2xl p-5">
          <p className="text-white/50 text-sm">
            Execution Rate
          </p>

          <h3 className="text-3xl font-bold mt-2">
            98%
          </h3>
        </div>
      </div>

      {/* Intent Queue */}
      <div className="space-y-4">
        {loading && (
          <div className="glass rounded-2xl p-8 animate-pulse h-28" />
        )}

        {executableIntents.map(
          (intent) => (
            <motion.div
              key={intent.id}
              whileHover={{
                scale: 1.01,
              }}
              className="glass rounded-2xl p-6"
            >
              <div className="flex items-start justify-between">
                {/* Left */}
                <div>
                  <div className="flex items-center gap-3">
                    <IconCpu className="text-cyan-400" />

                    <h3 className="text-xl font-semibold">
                      Intent #
                      {intent.id}
                    </h3>
                  </div>

                  <p className="text-white/50 mt-2">
                    Target:
                    {" "}
                    {
                      intent.targetPrice
                    }
                  </p>

                  <p className="text-white/40 text-sm mt-1">
                    Amount:
                    {" "}
                    {intent.amountIn}
                  </p>

                  <div className="flex items-center gap-2 mt-4">
                    <div className="w-2 h-2 rounded-full bg-yellow-400 animate-pulse" />

                    <span className="text-yellow-400 text-sm">
                      Awaiting execution
                    </span>
                  </div>
                </div>

                {/* Action */}
                <button
                  disabled={isPending}
                  onClick={() =>
                    handleExecute(
                      intent.id
                    )
                  }
                  className="px-5 py-3 rounded-2xl bg-gradient-to-r from-cyan-400 to-purple-500 text-black font-semibold flex items-center gap-2 disabled:opacity-50"
                >
                  <IconBolt size={18} />

                  Execute
                </button>
              </div>
            </motion.div>
          )
        )}
      </div>
    </motion.div>
  );
}