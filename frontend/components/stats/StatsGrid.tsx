"use client";

import { motion } from "framer-motion";
import {
  IconChartBar,
  IconCurrencyDollar,
  IconUsers,
  IconShieldCheck,
} from "@tabler/icons-react";

const stats = [
  {
    title: "Total Intents",
    value: "128",
    change: "+12.5%",
    icon: IconChartBar,
    glow: "cyan",
  },
  {
    title: "Total Volume",
    value: "$2.45M",
    change: "+18.7%",
    icon: IconCurrencyDollar,
    glow: "purple",
  },
  {
    title: "Active Solvers",
    value: "42",
    change: "+7.3%",
    icon: IconUsers,
    glow: "blue",
  },
  {
    title: "Success Rate",
    value: "98.6%",
    change: "+2.1%",
    icon: IconShieldCheck,
    glow: "green",
  },
];

export default function StatsGrid() {
  return (
    <section className="max-w-7xl mx-auto px-6 mt-10">
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-5">
        {stats.map((stat, index) => {
          const Icon = stat.icon;

          return (
            <motion.div
              key={index}
              whileHover={{
                y: -5,
                scale: 1.01,
              }}
              className="glass rounded-3xl p-6 relative overflow-hidden"
            >
              {/* Glow */}
              <div
                className={`absolute inset-0 opacity-10 blur-3xl ${
                  stat.glow === "cyan"
                    ? "bg-cyan-400"
                    : stat.glow === "purple"
                    ? "bg-purple-400"
                    : stat.glow === "blue"
                    ? "bg-blue-400"
                    : "bg-green-400"
                }`}
              />

              <div className="relative z-10">
                <div className="flex items-center justify-between">
                  <p className="text-white/70">
                    {stat.title}
                  </p>

                  <div className="p-2 rounded-xl bg-white/5 border border-white/10">
                    <Icon size={20} />
                  </div>
                </div>

                <h2 className="text-5xl font-bold mt-6">
                  {stat.value}
                </h2>

                <p className="text-green-400 mt-4">
                  {stat.change}
                </p>

                {/* Fake chart line */}
                <div className="mt-6 h-10 flex items-end gap-1">
                  {[20, 35, 25, 50, 40, 70, 60, 80].map(
                    (height, i) => (
                      <motion.div
                        key={i}
                        initial={{
                          height: 0,
                        }}
                        animate={{
                          height,
                        }}
                        transition={{
                          delay: i * 0.05,
                        }}
                        className="flex-1 rounded-full bg-gradient-to-t from-cyan-400 to-purple-500"
                      />
                    )
                  )}
                </div>
              </div>
            </motion.div>
          );
        })}
      </div>
    </section>
  );
}