// A small external store of RPC request lifecycle entries, fed by the
// `logRequests` interceptor in `rpc.ts` and rendered by the request-log panel in
// App.tsx. Each call adds a "pending" entry on start and flips it to "ok"/"error"
// (with a duration) on finish, a concrete demonstration of what an interceptor
// can observe that the fire-and-forget `onError` hook cannot.
export type RequestStatus = "pending" | "ok" | "error";

export type RequestLogEntry = {
  id: number;
  procedure: string;
  status: RequestStatus;
  startedAt: number;
  durationMs?: number;
};

const MAX_ENTRIES = 50;

let entries: RequestLogEntry[] = [];
let nextId = 1;
const listeners = new Set<() => void>();

const emit = () => {
  for (const notify of listeners) notify();
};

export const requestLog = {
  start(procedure: string): number {
    const id = nextId++;
    const entry: RequestLogEntry = { id, procedure, status: "pending", startedAt: Date.now() };
    entries = [entry, ...entries].slice(0, MAX_ENTRIES);
    emit();
    return id;
  },
  finish(id: number, status: Exclude<RequestStatus, "pending">, durationMs: number) {
    entries = entries.map((entry) => (entry.id === id ? { ...entry, status, durationMs } : entry));
    emit();
  },
  getSnapshot(): readonly RequestLogEntry[] {
    return entries;
  },
  subscribe(listener: () => void): () => void {
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  },
};
