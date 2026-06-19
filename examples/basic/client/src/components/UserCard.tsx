import type { AuthMeOutput } from "../rpc.gen";

type Props = {
  me: AuthMeOutput;
  onLogout: () => void;
};

export function UserCard({ me, onLogout }: Props) {
  return (
    <div className="card">
      <h2>Logged in as</h2>
      <p>
        <strong>{me.id}</strong> &mdash; {me.email}
      </p>
      <button type="button" className="btn-danger" onClick={onLogout}>
        Logout
      </button>
    </div>
  );
}
