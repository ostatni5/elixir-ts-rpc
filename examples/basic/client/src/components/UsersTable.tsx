import { useState } from "react";
import type { UpdateEmailResult } from "../App";
import type { Int64String, NaiveDateTimeString, UsersListOutput } from "../rpc.gen";

type Props = {
  users: UsersListOutput["users"];
  meta: UsersListOutput["meta"];
  onUpdateEmail: (id: string, email: string) => Promise<UpdateEmailResult>;
};

// datetime arrives as the branded number EpochMillis (DateTime is aliased to UnixMillis).
const fmtDateTime = (ms: number) => new Date(ms).toISOString().replace("T", " ").slice(0, 19);

// Helpers take branded wire types, not bare `string`, so the compiler rejects a
// plain string or a value branded for a different type. The point of branding.
const fmtNaive = (s: NaiveDateTimeString) => s.replace("T", " ").slice(0, 19);

// account_id is an `Int64String` the client must parse itself: the 64-bit value
// exceeds JS's safe integer range, so parsing as a number would silently round
// (Number("9007199254740993") === 9007199254740992). Codegen skips coercion here.
const fmtAccountId = (id: Int64String) => BigInt(id).toString();

function EmailCell({
  id,
  email,
  onUpdateEmail,
}: {
  id: string;
  email: string;
  onUpdateEmail: Props["onUpdateEmail"];
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(email);
  const [error, setError] = useState<Extract<UpdateEmailResult, { ok: false }> | null>(null);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    setSaving(true);
    setError(null);
    const result = await onUpdateEmail(id, draft);
    setSaving(false);
    if (result.ok) {
      setEditing(false);
    } else {
      setError(result);
    }
  };

  if (!editing) {
    return (
      <>
        {email}{" "}
        <button
          type="button"
          onClick={() => {
            setDraft(email);
            setError(null);
            setEditing(true);
          }}
        >
          Edit
        </button>
      </>
    );
  }

  return (
    <>
      <input type="text" value={draft} onChange={(e) => setDraft(e.target.value)} />
      <button type="button" className="btn-primary" disabled={saving} onClick={save}>
        {saving ? "Saving…" : "Save"}
      </button>
      <button type="button" onClick={() => setEditing(false)}>
        Cancel
      </button>
      {error && (
        <p className="error">
          {error.message}
          {/* Each error `source` drives a different affordance, the payoff of
              narrowing by source in App.tsx rather than collapsing every failure
              into one message. */}
          {error.kind === "validation" && error.field && <> (field: {error.field})</>}
          {error.kind === "auth" && <> - please log in again.</>}
          {error.kind === "transport" && (
            <>
              {" "}
              <button type="button" onClick={save}>
                Retry
              </button>
            </>
          )}
        </p>
      )}
    </>
  );
}

export function UsersTable({ users, meta, onUpdateEmail }: Props) {
  return (
    <div className="card">
      <h2>All users (via users.list)</h2>
      <p>
        Generated at <code>{fmtDateTime(meta.generated_at)}</code>
        {meta.range.since && (
          <>
            {" "}
            - created since <code>{fmtDateTime(meta.range.since)}</code>
          </>
        )}
      </p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Account ID</th>
              <th>Email</th>
              <th>Created</th>
              <th>Last login</th>
              <th>Birthday</th>
            </tr>
          </thead>
          <tbody>
            {users.map((u) => (
              <tr key={u.id}>
                <td>{u.id}</td>
                <td>
                  <code>{fmtAccountId(u.account_id)}</code>
                </td>
                <td>
                  <EmailCell id={u.id} email={u.email} onUpdateEmail={onUpdateEmail} />
                </td>
                <td>{fmtDateTime(u.created_at)}</td>
                <td>{fmtNaive(u.last_login_at)}</td>
                <td>{u.birthday ?? "-"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
