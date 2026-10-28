import { useState } from "react";
import toast from "react-hot-toast";
import { MapPin, Phone, ShieldAlert, User } from "lucide-react";

import useAdminData from "../../lib/useAdminData";
import { apiRequest } from "../../lib/api";
import DataState from "../../components/DataState";
import PageHeader from "../../components/PageHeader";

// SOS alerts need a faster refresh than other admin data.
export const SOS_POLL_MS = 10000;

const STATUS_STYLES = {
  active: "bg-red-600 text-white",
  safe: "bg-amber-100 text-amber-800",
  acknowledged: "bg-blue-100 text-blue-700",
  resolved: "bg-green-100 text-green-700",
};

const STATUS_LABELS = {
  active: "Active",
  safe: "Marked safe",
  acknowledged: "Acknowledged",
  resolved: "Resolved",
};

function formatTime(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString();
}

function PersonCard({ title, person, identity }) {
  if (!person) return null;
  return (
    <div className="rounded-xl border border-gray-100 bg-gray-50 p-4">
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500">{title}</p>
      <div className="flex items-center gap-3">
        {person.photoBase64 ? (
          <img
            src={`data:image/jpeg;base64,${person.photoBase64}`}
            alt=""
            className="h-12 w-12 rounded-full object-cover"
          />
        ) : (
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-gray-200">
            <User className="h-5 w-5 text-gray-500" />
          </span>
        )}
        <div className="min-w-0">
          <p className="font-semibold text-gray-900">
            {person.name} <span className="font-normal text-gray-500">({person.role})</span>
          </p>
          {person.phone ? (
            <a href={`tel:${person.phone}`} className="inline-flex items-center gap-1 text-sm text-blue-600 hover:underline">
              <Phone className="h-3.5 w-3.5" /> {person.phone}
            </a>
          ) : (
            <p className="text-sm text-gray-500">No phone on file</p>
          )}
          {person.email && <p className="truncate text-xs text-gray-500">{person.email}</p>}
        </div>
      </div>
      {identity && (
        <dl className="mt-3 grid grid-cols-2 gap-x-3 gap-y-1 text-xs">
          <dt className="text-gray-500">Verification</dt>
          <dd className="font-medium text-gray-800">{identity.verificationStatus || "—"}</dd>
          <dt className="text-gray-500">ID type</dt>
          <dd className="font-medium text-gray-800">{identity.idType || "—"}</dd>
          <dt className="text-gray-500">ID number</dt>
          <dd className="font-medium text-gray-800">{identity.maskedIdNumber || "—"}</dd>
        </dl>
      )}
    </div>
  );
}

function AlertCard({ alert, onUpdate }) {
  const [notes, setNotes] = useState(alert.adminNotes || "");
  const [saving, setSaving] = useState(false);
  const status = alert.statusKey || "active";
  const urgent = status === "active";
  const raiserIsWorker = alert.raisedBy?.role === "worker";
  const position = alert.position;

  async function update(nextStatus) {
    setSaving(true);
    try {
      const { item } = await apiRequest(`/api/admin/sos/${alert.id}`, {
        method: "PATCH",
        body: JSON.stringify({ status: nextStatus, adminNotes: notes }),
      });
      onUpdate(item);
      toast.success(nextStatus === "resolved" ? "Alert resolved." : "Alert acknowledged.");
    } catch (failure) {
      toast.error(failure.message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <article
      className={`rounded-2xl border bg-white p-5 shadow-sm ${urgent ? "border-red-500 ring-2 ring-red-200" : "border-gray-100"}`}
    >
      <header className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="font-display text-lg font-bold text-gray-900">
            {alert.jobTitle || "Booking"}{" "}
            <span className="text-sm font-normal text-gray-500">#{alert.requestId}</span>
          </p>
          <p className="text-sm text-gray-500">
            Raised {formatTime(alert.createdAt)} · pressed {alert.pressCount || 1}×
            {alert.safeAt && ` · marked safe ${formatTime(alert.safeAt)}`}
          </p>
        </div>
        <span className={`rounded-full px-3 py-1 text-xs font-semibold ${STATUS_STYLES[status] || STATUS_STYLES.active}`}>
          {STATUS_LABELS[status] || alert.status}
        </span>
      </header>

      <div className="grid gap-3 md:grid-cols-2">
        <PersonCard
          title="Needs help"
          person={alert.raisedBy}
          identity={raiserIsWorker ? alert.workerIdentity : null}
        />
        <PersonCard
          title="Other party"
          person={alert.otherParty}
          identity={raiserIsWorker ? null : alert.workerIdentity}
        />
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
        <span className="inline-flex items-center gap-1.5 text-gray-700">
          <MapPin className="h-4 w-4 text-gray-400" />
          {alert.jobAddress || "No job address"}
        </span>
        {position ? (
          <a
            href={`https://www.google.com/maps?q=${position.lat},${position.lng}`}
            target="_blank"
            rel="noreferrer"
            className="font-medium text-blue-600 hover:underline"
          >
            Open live GPS position{position.accuracy ? ` (±${Math.round(position.accuracy)} m)` : ""} ·{" "}
            {formatTime(alert.positionUpdatedAt)}
          </a>
        ) : (
          <span className="text-gray-500">No GPS position shared</span>
        )}
      </div>

      {status !== "resolved" ? (
        <div className="mt-4 space-y-3">
          <textarea
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            maxLength={5000}
            rows={2}
            placeholder="Actions taken (e.g. called client, contacted police)…"
            className="w-full rounded-lg border border-gray-200 p-2 text-sm"
          />
          <div className="flex flex-wrap gap-2">
            {status !== "acknowledged" && (
              <button
                type="button"
                disabled={saving}
                onClick={() => update("acknowledged")}
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                Acknowledge
              </button>
            )}
            <button
              type="button"
              disabled={saving}
              onClick={() => update("resolved")}
              className="rounded-lg bg-green-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              Resolve
            </button>
          </div>
        </div>
      ) : (
        <p className="mt-4 text-sm text-gray-600">
          Resolved by {alert.handledBy || "admin"} {formatTime(alert.handledAt)}
          {alert.adminNotes && <> — {alert.adminNotes}</>}
        </p>
      )}
    </article>
  );
}

export default function SosAlerts() {
  const { data: alerts, setData: setAlerts, loading, error } = useAdminData("sos", [], SOS_POLL_MS);
  const open = alerts.filter((alert) => alert.statusKey !== "resolved");
  const resolved = alerts.filter((alert) => alert.statusKey === "resolved");

  const replace = (item) =>
    setAlerts((current) => current.map((alert) => (alert.id === item.id ? item : alert)));

  return (
    <div>
      <PageHeader title="SOS alerts" breadcrumb={["Dashboard", "SOS alerts"]} />
      <DataState loading={loading} error={error} />
      {!loading && !alerts.length && (
        <div className="flex items-center gap-3 rounded-2xl bg-white p-6 text-gray-600">
          <ShieldAlert className="h-5 w-5 text-gray-400" /> No SOS alerts have been raised.
        </div>
      )}
      <div className="space-y-4">
        {open.map((alert) => <AlertCard key={alert.id} alert={alert} onUpdate={replace} />)}
      </div>
      {resolved.length > 0 && (
        <>
          <h2 className="mb-3 mt-8 text-sm font-semibold uppercase tracking-wide text-gray-500">Resolved</h2>
          <div className="space-y-4">
            {resolved.map((alert) => <AlertCard key={alert.id} alert={alert} onUpdate={replace} />)}
          </div>
        </>
      )}
    </div>
  );
}
