import { isMiddlewareError, isTransportError } from "@elixir-ts-rpc/client";
import { useEffect, useState } from "react";
import { loginUrl, logout, registerUrl } from "./api/auth";
import { RequestLog } from "./RequestLog";
import { rpc } from "./rpc";
import type { EpochMillis, RpcAuthMeOutput, RpcUsersListOutput } from "./rpc.gen";

type Session = {
  me: RpcAuthMeOutput;
  users: RpcUsersListOutput["users"];
  count: number;
};
type State =
  | { status: "loading" }
  | { status: "anonymous" }
  | { status: "ready"; session: Session }
  | { status: "error"; message: string };

const fmt = (ms: EpochMillis | null) => (ms ? new Date(ms).toLocaleString() : "—");

const loadSession = async (): Promise<Session> => {
  const [me, usersData, counter] = await Promise.all([
    rpc.auth.me({}),
    rpc.users.list({}),
    rpc.counter.get({}),
  ]);
  return { me, users: usersData.users, count: counter.count };
};

// RequireUser halts unauthenticated calls with a middleware error (source:
// "middleware"). `loadSession` races several calls, so rather than guess which
// one rejected first, `isMiddlewareError` recognizes the auth halt from any of
// them by its provenance — the signal to send the user to Phoenix's login page.
const toErrorState = (e: unknown): State => {
  if (isMiddlewareError(e)) return { status: "anonymous" };
  if (isTransportError(e)) return { status: "error", message: e.message };
  throw e;
};

export default function App() {
  const [state, setState] = useState<State>({ status: "loading" });

  useEffect(() => {
    loadSession().then(
      (session) => setState({ status: "ready", session }),
      (e) => setState(toErrorState(e)),
    );
  }, []);

  // A mutating RPC call: adjust the counter on the server and reflect the
  // authoritative new value the handler returns. A cross-cutting `unauthorized`
  // is the central `onError` observer's concern (see rpc.ts), not this call's —
  // adjust handles only its own outcome.
  const adjust = async (delta: number) => {
    const { count } = await rpc.counter.adjust({ delta });
    setState((prev) =>
      prev.status === "ready" ? { ...prev, session: { ...prev.session, count } } : prev,
    );
  };

  // Two calls whose only purpose is to show up in the request log: `demo.slow`
  // sits "pending" for ~5s before resolving; `demo.fail` always returns its
  // `demo_failure` domain error — a call-site concern, so we handle (ignore) it
  // here. We don't await either; the interceptor records both edges.
  const runSlowCall = () => void rpc.demo.slow({});
  const runFailingCall = () => void rpc.demo.fail({}).catch(() => {});

  return (
    <div>
      <h1>elixir-ts-rpc · Phoenix example</h1>
      <p className="lede">
        Typed RPC on a Phoenix app that reuses Phoenix's generated auth and CSRF protection. This
        SPA writes no auth code — it just reads the session Phoenix already established.
      </p>

      {state.status === "loading" && <p>Loading…</p>}

      {state.status === "error" && (
        <p className="error">Could not reach the server: {state.message}</p>
      )}

      {state.status === "anonymous" && (
        <div className="card">
          <p>You are not logged in.</p>
          <p>
            <a className="btn" href={loginUrl}>
              Log in
            </a>{" "}
            <a href={registerUrl}>or register</a> — these are Phoenix's generated pages. After
            logging in you'll return here and the RPC calls will succeed using the same session
            cookie.
          </p>
        </div>
      )}

      {state.status === "ready" && (
        <>
          <div className="card">
            <strong>Logged in as {state.session.me.email}</strong> (id {state.session.me.id})
            <button type="button" className="btn" onClick={logout}>
              Log out
            </button>
          </div>

          <h2>Your counter (a mutating RPC call)</h2>
          <div className="card counter">
            <button type="button" className="btn" onClick={() => adjust(-1)}>
              −
            </button>
            <span className="count">{state.session.count}</span>
            <button type="button" className="btn" onClick={() => adjust(1)}>
              +
            </button>
            <span className="hint">persisted per-user in the database via `counter.adjust`</span>
          </div>

          <h2>Exercise the request log</h2>
          <div className="card">
            <div className="actions">
              <button type="button" className="btn" onClick={runSlowCall}>
                Slow call (5s)
              </button>
              <button type="button" className="btn" onClick={runFailingCall}>
                Failing call
              </button>
            </div>
            <span className="hint">
              watch the log below — the slow call sits “pending”, the failing call flips to “error”
            </span>
          </div>

          <h2>Users (from the database, via RPC)</h2>
          <table>
            <thead>
              <tr>
                <th>id</th>
                <th>email</th>
                <th>confirmed at</th>
                <th>registered at</th>
              </tr>
            </thead>
            <tbody>
              {state.session.users.map((u) => (
                <tr key={u.id}>
                  <td>{u.id}</td>
                  <td>{u.email}</td>
                  <td>{fmt(u.confirmed_at)}</td>
                  <td>{fmt(u.inserted_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}

      <RequestLog />
    </div>
  );
}
