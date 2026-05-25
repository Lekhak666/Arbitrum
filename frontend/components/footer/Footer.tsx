"use client";

import Image from "next/image";
import { motion } from "framer-motion";

const footerLinks = {
  Product: [
    "Dashboard",
    "Intents",
    "Portfolio",
  ],
  Resources: [
    "Documentation",
    "FAQs",
    "API Reference",
  ],
  Community: [
    "Discord",
    "Twitter",
    "GitHub",
  ],
};

export default function Footer() {
  return (
    <footer className="max-w-7xl mx-auto px-6 mt-16 pb-12">
      {/* Glow Line */}
      <div className="h-px w-full bg-gradient-to-r from-cyan-400 via-purple-500 to-cyan-400 opacity-40 mb-10" />

      <div className="grid grid-cols-1 md:grid-cols-5 gap-10">
        {/* Brand */}
        <div className="md:col-span-2">
          <motion.div
            whileHover={{
              scale: 1.03,
            }}
            className="flex items-center gap-4"
          >
            <Image
              src="/veilswap.png"
              alt="Veil Swap"
              width={60}
              height={60}
              loading="eager"
              className="drop-shadow-[0_0_25px_rgba(0,255,255,0.55)]"
            />

            <div>
              <h2 className="text-3xl font-bold">
                Veil Swap
              </h2>

              <p className="text-white/60 mt-2 max-w-sm">
                Intent-based trading protocol
                built for smarter DeFi.
              </p>
            </div>
          </motion.div>
        </div>

        {/* Links */}
        {Object.entries(footerLinks).map(
          ([title, links]) => (
            <div key={title}>
              <h3 className="font-semibold text-lg mb-5">
                {title}
              </h3>

              <ul className="space-y-3">
                {links.map((link) => (
                  <li
                    key={link}
                    className="text-white/60 hover:text-cyan-400 transition-all cursor-pointer"
                  >
                    {link}
                  </li>
                ))}
              </ul>
            </div>
          )
        )}
      </div>

      {/* Bottom */}
      <div className="mt-12 pt-6 border-t border-white/10 flex flex-col md:flex-row items-center justify-between gap-4">
        <p className="text-white/40">
          © 2026 Veil Swap. All rights reserved.
        </p>

        <p className="text-white/40">
          Built with ❤️ for the future of DeFi.
        </p>
      </div>
    </footer>
  );
}