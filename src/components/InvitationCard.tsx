import { useState } from "react";
import { Link } from "react-router-dom";
import type { Inviter } from "../services/invitations";
import { acceptInvitation, NotConnectedError } from "../services/invitations";
import DownloadCTA from "./DownloadCTA";

export function Avatar({ inviter }: { inviter: Inviter }) {
  return inviter.avatarUrl ? (
    <img className="avatar" src={inviter.avatarUrl} alt="" />
  ) : (
    <div className="avatar" aria-hidden="true">
      {inviter.displayName.charAt(0).toUpperCase()}
    </div>
  );
}

export default function InvitationCard({
  token,
  inviter,
}: {
  token: string;
  inviter: Inviter;
}) {
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  async function onAccept() {
    setBusy(true);
    setNotice(null);
    try {
      await acceptInvitation(token);
    } catch (e) {
      setNotice(
        e instanceof NotConnectedError
          ? "Accepting isn’t connected yet in this preview, so nothing was accepted."
          : "Something went wrong. Please try again."
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card invite">
      <Avatar inviter={inviter} />
      <h1>You’ve been invited to StudyUP</h1>
      <p className="lead">
        <strong>{inviter.displayName}</strong> wants to connect with you on StudyUP
        so you can compare study progress and keep each other going.
      </p>
      <div className="stack">
        <button
          type="button"
          className="btn btn-primary"
          onClick={onAccept}
          disabled={busy}
        >
          {busy ? "Working…" : "Accept invitation"}
        </button>
        <DownloadCTA variant="secondary" label="Download StudyUP" />
      </div>
      {notice && (
        <p className="note small" role="status" aria-live="polite" style={{ marginTop: "0.5rem" }}>
          {notice}
        </p>
      )}
      <p className="small" style={{ marginTop: "1rem" }}>
        <Link to="/">Back to StudyUP</Link>
      </p>
    </div>
  );
}
