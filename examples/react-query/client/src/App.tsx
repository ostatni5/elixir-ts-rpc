import { isMiddlewareError, type RpcError, type TransportError } from "@elixir-ts-rpc/client";
import type { RpcErrorOf } from "@elixir-ts-rpc/react";
import { skipToken, useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useState } from "react";
import { login, logout } from "./api/auth";
import { rpc } from "./rpc";

export default function App() {
  const [authed, setAuthed] = useState(false);
  return authed ? (
    <Dashboard onLogout={() => setAuthed(false)} />
  ) : (
    <Login onLogin={() => setAuthed(true)} />
  );
}

function Login({ onLogin }: { onLogin: () => void }) {
  const [username, setUsername] = useState("alice");
  const [password, setPassword] = useState("wonderland");
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setPending(true);
    setError(null);
    try {
      await login(username, password);
      onLogin();
    } catch (err) {
      setError(err instanceof Error ? err.message : "login failed");
    } finally {
      setPending(false);
    }
  };

  return (
    <main className="card">
      <h1>elixir-ts-rpc — React + TanStack Query</h1>
      <p>
        Log in (default alice / wonderland), then queries and mutations run through the adapter.
      </p>
      <form onSubmit={submit} className="login">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          placeholder="username"
        />
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="password"
        />
        <button type="submit" className="btn-primary" disabled={pending}>
          {pending ? "Logging in…" : "Log in"}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
    </main>
  );
}

function Dashboard({ onLogout }: { onLogout: () => void }) {
  const queryClient = useQueryClient();
  // Empty-input procedures need no argument.
  const me = rpc.auth.me.useQuery();
  const users = rpc.users.list.useQuery();

  const handleLogout = async () => {
    await logout();
    // Drop cached data so the next user to log in never sees this one's.
    queryClient.clear();
    onLogout();
  };

  // A middleware `unauthorized` on any query means the session is gone. It is the
  // one cross-cutting error arm, so handle it once here rather than per-view.
  if (isSessionExpired(me.error) || isSessionExpired(users.error)) {
    return (
      <main className="card">
        <p className="error">Your session expired.</p>
        <button type="button" className="btn-primary" onClick={handleLogout}>
          Back to login
        </button>
      </main>
    );
  }

  return (
    <main className="card">
      <header className="topbar">
        <h1>Users</h1>
        <span>
          {me.data ? `signed in as ${me.data.email}` : "…"}{" "}
          <button type="button" onClick={handleLogout}>
            Log out
          </button>
        </span>
      </header>

      <UserLookup />

      {users.isPending && <p>Loading users…</p>}
      {users.isError && <p className="error">Failed to load: {users.error.message}</p>}
      {users.data && (
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Email</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {users.data.users.map((u) => (
              // Hovering a row warms the by-ID lookup cache below: `queryOptions`
              // composes into any TanStack API — here `prefetchQuery`, not the bound hook.
              <tr
                key={u.id}
                onMouseEnter={() =>
                  queryClient.prefetchQuery(rpc.users.get.queryOptions({ id: u.id }))
                }
              >
                <td>{u.id}</td>
                <td>
                  <EmailEditor id={u.id} email={u.email} />
                </td>
                <td>{new Date(u.created_at).toISOString().slice(0, 10)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </main>
  );
}

// A required-input query: `users.get` takes an id, so `useQuery` requires it.
// `skipToken` disables the fetch until an id is typed — the type-safe alternative
// to `enabled`, with no `if` around the hook.
function UserLookup() {
  const [id, setId] = useState("");
  const result = rpc.users.get.useQuery(id === "" ? skipToken : { id });

  return (
    <p className="lookup">
      Look up by ID:{" "}
      <input value={id} onChange={(e) => setId(e.target.value)} placeholder="user id" />
      {id !== "" && result.isPending && <span> looking up…</span>}
      {result.isError && <span className="error"> {result.error.message}</span>}
      {result.data && <span> → {result.data.email}</span>}
    </p>
  );
}

function EmailEditor({ id, email }: { id: string; email: string }) {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState(email);

  const update = rpc.users.update.useMutation({
    // Refetch the list so the edit shows immediately; the key targets every
    // users.list query regardless of its filter input.
    onSuccess: () => queryClient.invalidateQueries({ queryKey: rpc.users.list.queryKey() }),
  });

  return (
    <span className="email-editor">
      <input value={draft} onChange={(e) => setDraft(e.target.value)} />
      <button
        type="button"
        className="btn-primary"
        disabled={update.isPending || draft === email}
        onClick={() => update.mutate({ id, email: draft })}
      >
        {update.isPending ? "Saving…" : "Save"}
      </button>
      {update.isError && <span className="error"> {describeUpdateError(update.error)}</span>}
    </span>
  );
}

function isSessionExpired(error: RpcError | null): boolean {
  return error !== null && isMiddlewareError(error) && error.code === "unauthorized";
}

// The hook error is the procedure's declared union OR a client-synthesized
// transport error. `.isError` narrows to the declared arm (leaving transport to
// the fall-through), and `error.code` is then an exhaustive literal union.
type UpdateError = RpcErrorOf<typeof rpc.users.update>;

function describeUpdateError(error: UpdateError | TransportError): string {
  if (!rpc.users.update.isError(error)) return error.message;
  switch (error.code) {
    case "invalid_email":
      return error.details?.field
        ? `${error.message} (field: ${error.details.field})`
        : error.message;
    case "email_taken":
      return "That email is already in use.";
    case "not_found":
      return "That user no longer exists.";
    case "unauthorized":
      return "Your session expired — log in again.";
  }
}
