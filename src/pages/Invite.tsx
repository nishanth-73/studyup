import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { LogoMark } from "../components/Logo";
import InvitationCard from "../components/InvitationCard";
import { useTitle } from "../components/Layout";
import { fetchInvitation, type InvitationState } from "../services/invitations";

type View = { kind: "loading" } | { kind: "error" } | { kind: "done"; state: InvitationState };

const messages: Record<string, { h: string; p: string }> = {
  invalid: { h: "This invitation link isn’t valid", p: "Check that the whole link was copied, or ask your friend to send a new one." },
  expired: { h: "This invitation has expired", p: "Ask your friend to send you a fresh invitation link." },
  already_accepted: { h: "This invitation was already used", p: "Invitations work once. If you’re already connected, you’re all set." },
};

export default function Invite() {
  useTitle("You’re invited · StudyUP");
  const { token = "" } = useParams();
  const [view, setView] = useState<View>({ kind: "loading" });
  const [attempt, setAttempt] = useState(0);

  const load = useCallback(() => {
    let live = true;
    setView({ kind: "loading" });
    // TODO(invite-validate): token is read from the route and stays in the URL; never send it to analytics or third parties.
    fetchInvitation(token).then((state) => live && setView({ kind: "done", state })).catch(() => live && setView({ kind: "error" }));
    return () => { live = false; };
  }, [token]);
  useEffect(load, [load, attempt]);

  return (
    <div className="invite-page">
      <header className="wrap invite-head"><Link to="/" className="logo" aria-label="StudyUP home"><LogoMark /> <span>StudyUP</span></Link></header>
      <main className="wrap invite-main" id="main">
        {view.kind === "loading" && <div className="card invite" role="status" aria-live="polite"><div className="spinner" aria-hidden="true" /><p>Checking your invitation…</p></div>}
        {view.kind === "error" && (
          <div className="card invite" role="alert">
            <h1>We couldn’t load this invitation</h1>
            <p className="muted">Check your connection and try again.</p>
            <button className="btn btn-primary" onClick={() => setAttempt((a) => a + 1)}>Try again</button>
          </div>
        )}
        {view.kind === "done" && view.state.status === "ready" && <InvitationCard token={token} inviter={view.state.inviter} />}
        {view.kind === "done" && view.state.status !== "ready" && (
          <div className="card invite">
            <h1>{messages[view.state.status].h}</h1>
            <p className="muted">{messages[view.state.status].p}</p>
            <Link className="btn btn-primary" to="/">Go to StudyUP</Link>
          </div>
        )}
      </main>
    </div>
  );
}
