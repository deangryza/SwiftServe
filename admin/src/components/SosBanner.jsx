import { Link, useLocation } from "react-router-dom";
import { Siren } from "lucide-react";

import useAdminData from "../lib/useAdminData";
import { SOS_POLL_MS } from "../page/sos/SosAlerts";

// Shown on every dashboard page while an SOS alert is still active.
export default function SosBanner() {
  const { pathname } = useLocation();
  const { data: alerts } = useAdminData("sos", [], SOS_POLL_MS);
  const active = alerts.filter((alert) => alert.statusKey === "active").length;
  if (!active || pathname.startsWith("/dashboard/sos")) return null;
  return (
    <Link
      to="/dashboard/sos"
      role="alert"
      className="flex items-center gap-3 bg-red-600 px-4 py-3 text-sm font-semibold text-white hover:bg-red-700 sm:px-6 lg:px-8"
    >
      <Siren className="h-5 w-5 shrink-0 animate-pulse" />
      {active === 1 ? "1 active SOS alert" : `${active} active SOS alerts`} — someone needs help. View now →
    </Link>
  );
}
