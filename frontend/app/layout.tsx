import "./globals.css";
import { Providers } from "./providers";
import Web3Provider from "@/components/providers/Web3Provider";
import CyberBackground from "@/components/background/CyberBackground";
import { Toaster } from "sonner";

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="antialiased">
        <Web3Provider>
          <Toaster richColors position="top-right" />

          <CyberBackground />
          <div className="relative z-10">
            {children}
          </div>
        </Web3Provider>
      </body>
    </html>
  );
}