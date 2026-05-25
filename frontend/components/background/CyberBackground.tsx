"use client";

import { useEffect, useState } from "react";

import { motion } from "framer-motion";

export default function CyberBackground() {
  const [mounted, setMounted] =
    useState(false);

  const [mousePosition, setMousePosition] =
    useState({
      x: 0,
      y: 0,
    });

  useEffect(() => {
    setMounted(true);

    const handleMouseMove = (
      e: MouseEvent
    ) => {
      setMousePosition({
        x: e.clientX,
        y: e.clientY,
      });
    };

    window.addEventListener(
      "mousemove",
      handleMouseMove
    );

    return () => {
      window.removeEventListener(
        "mousemove",
        handleMouseMove
      );
    };
  }, []);

  // Prevent hydration mismatch
  if (!mounted) return null;

  return (
    <div className="fixed inset-0 overflow-hidden pointer-events-none z-0">
      {/* GRID */}
      <div
        className="absolute inset-0 opacity-[0.07]"
        style={{
          backgroundImage: `
            linear-gradient(rgba(255,255,255,0.08) 1px, transparent 1px),
            linear-gradient(90deg, rgba(255,255,255,0.08) 1px, transparent 1px)
          `,
          backgroundSize:
            "50px 50px",
        }}
      />

      {/* CYAN ORB */}
      <motion.div
        animate={{
          x: mousePosition.x - 250,
          y: mousePosition.y - 250,
        }}
        transition={{
          type: "spring",
          stiffness: 50,
          damping: 20,
        }}
        className="absolute w-[500px] h-[500px] rounded-full bg-cyan-500/20 blur-[120px]"
      />

      {/* PURPLE ORB */}
      <motion.div
        animate={{
          x:
            mousePosition.x - 600,
          y:
            mousePosition.y - 600,
        }}
        transition={{
          type: "spring",
          stiffness: 30,
          damping: 25,
        }}
        className="absolute w-[700px] h-[700px] rounded-full bg-purple-500/20 blur-[140px]"
      />

      {/* PARTICLES */}
      {[...Array(30)].map((_, i) => {
        const randomX =
          Math.random() * window.innerWidth;

        const randomY =
          Math.random() * window.innerHeight;

        return (
          <motion.div
            key={i}
            initial={{
              x: randomX,
              y: randomY,
              opacity:
                Math.random() * 0.5,
            }}
            animate={{
              y: [
                randomY,
                Math.random() *
                  window.innerHeight,
              ],

              opacity: [
                0.2,
                0.8,
                0.2,
              ],
            }}
            transition={{
              duration:
                10 +
                Math.random() * 10,

              repeat: Infinity,

              ease: "linear",
            }}
            className="absolute w-1 h-1 rounded-full bg-cyan-300"
          />
        );
      })}

      {/* VIGNETTE */}
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,transparent_20%,#030303_100%)]" />
    </div>
  );
}