import { isMiddlewareError, isTransportError } from "@elixir-ts-rpc/client";
import { useState } from "react";
import { login, logout } from "./api/auth";
import { LoginForm } from "./components/LoginForm";
import { UserCard } from "./components/UserCard";
import { UsersTable } from "./components/UsersTable";
import { rpc } from "./rpc";
import type { AuthMeOutput, EpochMillis, UsersListOutput } from "./rpc.gen";

type Session = {
  me: AuthMeOutput;
  users: UsersListOutput["users"];
  meta: UsersListOutput["meta"];
};

// Each failure kind maps to one error `source`, so the UI can react differently:
// a validation error points at the offending field, an auth error sends the user
// back to login, a transport error offers a retry.
export type UpdateEmailResult =
  | { ok: true }
  | { ok: false; kind: "validation"; message: string; field: string | null }
  | { ok: false; kind: "auth"; message: string }
  | { ok: false; kind: "transport"; message: string };

export default function App() {
  const [session, setSession] = useState<Session | null>(null);

  const handleLogin = async (username: string, password: string) => {
    await login(username, password);
    const [me, usersData] = await Promise.all([
      rpc.auth.me({}),
      rpc.users.list({
        // DateTime is aliased to RpcElixir.UnixMillis, so datetime crosses the wire as
        // the branded number EpochMillis. Brand the epoch-ms value explicitly on input.
        filter: { since: Date.parse("2024-01-01T00:00:00Z") as EpochMillis },
      }),
    ]);
    setSession({ me, users: usersData.users, meta: usersData.meta });
  };

  const handleLogout = async () => {
    await logout();
    setSession(null);
  };

  // `rpc.users.update.isError` checks `e.code` at runtime and narrows to this
  // call's typed error union. `isTransportError` catches the client-synthesized
  // codes (network_error, …) with a typed `e.code` of its own.
  const handleUpdateEmail = async (id: string, email: string): Promise<UpdateEmailResult> => {
    try {
      const updated = await rpc.users.update({ id, email });
      setSession((prev) =>
        prev
          ? {
              ...prev,
              users: prev.users.map((u) => (u.id === id ? { ...u, email: updated.email } : u)),
            }
          : prev,
      );
      return { ok: true };
    } catch (e) {
      if (rpc.users.update.isError(e)) {
        // `unauthorized` is contributed by the RequireUser middleware (source:
        // "middleware") and carries no `field` detail. Narrowing by source rather
        // than by magic-string code lets TS prove the remaining arm is the
        // handler's domain error, so `e.details?.field` below is typed, no code
        // check needed.
        if (isMiddlewareError(e)) {
          return { ok: false, kind: "auth", message: e.message };
        }
        return {
          ok: false,
          kind: "validation",
          message: e.message,
          field: e.details?.field ?? null,
        };
      }
      if (isTransportError(e)) {
        return { ok: false, kind: "transport", message: e.message };
      }
      throw e;
    }
  };

  return (
    <div>
      <h1>elixir-ts-rpc basic demo</h1>
      {session ? (
        <>
          <UserCard me={session.me} onLogout={handleLogout} />
          <UsersTable users={session.users} meta={session.meta} onUpdateEmail={handleUpdateEmail} />
        </>
      ) : (
        <LoginForm onSubmit={handleLogin} />
      )}
    </div>
  );
}
