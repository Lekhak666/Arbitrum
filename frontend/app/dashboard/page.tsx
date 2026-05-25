import Navbar from "@/components/layout/Navbar";
import Hero from "@/components/hero/Hero";
import StatsGrid from "@/components/stats/StatsGrid";

import CreateIntentPanel from "@/components/intents/CreateIntentPanel";
import RecentIntents from "@/components/intents/RecentIntents";
import RevealIntentPanel from "@/components/intents/RevealIntentPanel";
import SolverDashboard from "@/components/solver/SolverDashboard";
import EventFeed from "@/components/events/EventFeed";

import Footer from "@/components/footer/Footer";

export default function DashboardPage() {
  return (
    <main className="min-h-screen pb-10">
      <Navbar />

      <Hero />

      <StatsGrid />

      {/* Intent Panels */}
      <section className="max-w-7xl mx-auto px-6 mt-8">
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <div className="space-y-6">
          <CreateIntentPanel />
          <RevealIntentPanel />
          </div>

          <RecentIntents />
        </div>

        <div className="mt-6">
          <EventFeed />
        </div>

        <div className="mt-6">
          <SolverDashboard />
        </div>
      </section>

      <Footer />
    </main>
  );
}