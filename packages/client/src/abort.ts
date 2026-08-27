// Exported for direct testing — the runtime path is selected by `combine`
// below, which prefers native `AbortSignal.any` when available.
export function combineSignalsPolyfill(signals: AbortSignal[]): AbortSignal {
  const controller = new AbortController();

  for (const s of signals) {
    if (s.aborted) {
      controller.abort(s.reason);
      return controller.signal;
    }
  }

  const subscriptions = signals.map((signal) => ({ signal, onAbort: () => {} }));

  for (const sub of subscriptions) {
    sub.onAbort = () => {
      controller.abort(sub.signal.reason);
      // Drop sibling listeners too: once one signal fires the others are moot,
      // and leaving them attached would leak (the `once` option only clears the
      // one that fired).
      for (const other of subscriptions) {
        other.signal.removeEventListener("abort", other.onAbort);
      }
    };
    sub.signal.addEventListener("abort", sub.onAbort, { once: true });
  }

  return controller.signal;
}

const combine =
  typeof AbortSignal.any === "function"
    ? (signals: AbortSignal[]) => AbortSignal.any(signals)
    : combineSignalsPolyfill;

export function combineSignals(
  a: AbortSignal | undefined,
  b: AbortSignal | undefined,
): AbortSignal | undefined {
  if (!a && !b) return undefined;
  if (!a) return b;
  if (!b) return a;
  return combine([a, b]);
}
