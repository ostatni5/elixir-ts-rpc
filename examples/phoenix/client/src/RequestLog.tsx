import { useSyncExternalStore } from "react";
import { type RequestStatus, requestLog } from "./request-log";

const fmtTime = (ms: number) =>
  `${new Date(ms).toLocaleTimeString(undefined, { hour12: false })}.${String(ms % 1000).padStart(3, "0")}`;

const label: Record<RequestStatus, string> = {
  pending: "⏳ pending",
  ok: "✓ ok",
  error: "✕ error",
};

// Renders the lifecycle entries the `logRequests` interceptor records — each RPC
// appears the moment it starts (pending) and updates in place when it finishes.
export function RequestLog() {
  const entries = useSyncExternalStore(requestLog.subscribe, requestLog.getSnapshot);
  if (entries.length === 0) return null;

  return (
    <>
      <h2>RPC request log (recorded by an interceptor)</h2>
      <table className="request-log">
        <thead>
          <tr>
            <th>procedure</th>
            <th>status</th>
            <th>started</th>
            <th>duration</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id}>
              <td>{entry.procedure}</td>
              <td>{label[entry.status]}</td>
              <td>{fmtTime(entry.startedAt)}</td>
              <td>{entry.durationMs == null ? "…" : `${Math.round(entry.durationMs)}ms`}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
