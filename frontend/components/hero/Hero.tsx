"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { IconArrowDown } from "@tabler/icons-react";

export default function Hero() {
  return (
    <section className="max-w-7xl mx-auto px-6 pt-20 pb-16">
      <div className="grid lg:grid-cols-2 gap-10 items-center">
        {/* Left */}
        <div>
          <motion.h1
            initial={{
              opacity: 0,
              y: 20,
            }}
            animate={{
              opacity: 1,
              y: 0,
            }}
            transition={{
              duration: 0.7,
            }}
            className="text-6xl md:text-7xl font-black leading-tight"
          >
            <span className="neon-text">
              Trade Smarter.
            </span>

            <br />

            <span className="text-purple-400">
              Let Intents
            </span>

            <br />

            Do The Rest.
          </motion.h1>

          <p className="mt-8 text-xl text-white/70 max-w-xl leading-relaxed">
            Create on-chain intents.
            Solvers compete.
            You get the best execution.
          </p>

          <div className="mt-10 flex items-center gap-4">
            <button className="px-8 py-4 rounded-2xl bg-cyan-400 text-black font-semibold glow-cyan hover:scale-105 transition-all">
              Create Intent
            </button>

            <button className="glass px-8 py-4 rounded-2xl hover:bg-white/10 transition-all">
              Explore Intents
            </button>
          </div>

          <div className="mt-8 inline-flex items-center gap-3 glass rounded-2xl px-5 py-3">
            <div className="w-3 h-3 bg-green-400 rounded-full animate-pulse" />

            <span className="text-white/80">
              Network: Arbitrum Chain
            </span>
          </div>
        </div>

        {/* Right */}
        <motion.div
          animate={{
            y: [0, -10, 0],
          }}
          transition={{
            duration: 4,
            repeat: Infinity,
          }}
          className="relative flex justify-center"
        >
          <div className="absolute w-[420px] h-[420px] rounded-full border border-cyan-400/20 animate-spin [animation-duration:20s]" />

          <div className="absolute w-[320px] h-[320px] rounded-full border border-purple-400/20 animate-spin [animation-duration:12s]" />

          <Image
            src="/veilswap.png"
            alt="Veil Swap   Logo"
            width={420}
            height={420}
            loading="eager"
            className="drop-shadow-[0_0_45px_rgba(0,255,255,0.55)]"
          />
        </motion.div>
      </div>

      {/* Scroll */}
      <div className="flex justify-center mt-20">
        <button className="glass p-4 rounded-full glow-cyan animate-bounce">
          <IconArrowDown />
        </button>
      </div>
    </section>
  );
}