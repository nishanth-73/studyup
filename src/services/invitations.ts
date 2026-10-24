/**
 * Invitation service ADAPTER (mock). Replace the bodies of the two functions below with real API calls.
 * The UI only depends on the types and function signatures in this file.
 *
 * Mock tokens for previewing each state (visit /invite/<token>):
 *   valid-demo-token    -> ready          expired-demo-token -> expired
 *   used-demo-token     -> already accepted    error-demo-token -> network error
 *   bad                 -> invalid (too short / malformed)    anything else well-formed -> ready
 */
export type Inviter = { displayName: string; avatarUrl?: string };
export type InvitationState =
  | { status: "ready"; inviter: Inviter }
  | { status: "expired" | "already_accepted" | "invalid" };

export class NotConnectedError extends Error {
  constructor() { super("Invitation acceptance is not connected to a backend yet."); }
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** TODO(invite-validate): Call a secure backend endpoint that returns ONLY inviter name/avatar + status. */
export async function fetchInvitation(token: string): Promise<InvitationState> {
  await wait(700);
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(token)) return { status: "invalid" };
  if (token.includes("error")) throw new Error("Mock network failure");
  if (token.includes("expired")) return { status: "expired" };
  if (token.includes("used")) return { status: "already_accepted" };
  // TODO(real-profile): replace placeholder with the inviter's real profile name and avatar.
  return { status: "ready", inviter: { displayName: "Your friend" } };
}

/**
 * TODO(invite-accept): Require authentication, then call a server-side single-use accept function.
 * TODO(auth): If logged out, send the visitor to login/signup with a validated redirect back to /invite/:token.
 * Intentionally throws: this build never pretends an invitation was accepted.
 */
export async function acceptInvitation(_token: string): Promise<never> {
  await wait(400);
  throw new NotConnectedError();
}
