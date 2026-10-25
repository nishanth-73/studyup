/**
 * Invitation service connected to Supabase backend.
 * Provides safe public invite preview and token preservation for deferred deep linking.
 */

export type Inviter = { displayName: string; avatarUrl?: string };
export type InvitationState =
  | { status: "ready"; inviter: Inviter }
  | { status: "expired" | "already_accepted" | "invalid" };

export class NotConnectedError extends Error {
  constructor(message?: string) {
    super(message || "Friend connections require the StudyUP app or an active StudyUP account.");
  }
}

// Fallback config from build-time / runtime environment
const DEFAULT_SUPABASE_URL = "https://rtkdriuafodgnljbhnpn.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0a2RyaXVhZm9kZ25samJobnBuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIxNjIxMzMsImV4cCI6MjEwNzczODEzM30.MGKN5wAWy52OK0O_p6ip7_jzuSHooDM73UlpwGkcels";

let cachedConfig: { supabaseUrl: string; supabaseAnonKey: string } | null = null;

async function getClientConfig(): Promise<{ supabaseUrl: string; supabaseAnonKey: string }> {
  if (cachedConfig) return cachedConfig;
  try {
    const res = await fetch("/api/config");
    if (res.ok) {
      const data = await res.json();
      if (data.supabaseUrl && data.supabaseAnonKey) {
        cachedConfig = { supabaseUrl: data.supabaseUrl, supabaseAnonKey: data.supabaseAnonKey };
        return cachedConfig;
      }
    }
  } catch (_) {
    // Fall back to embedded production defaults
  }
  cachedConfig = { supabaseUrl: DEFAULT_SUPABASE_URL, supabaseAnonKey: DEFAULT_SUPABASE_ANON_KEY };
  return cachedConfig;
}

/**
 * Validates and fetches inviter details for an invitation token from Supabase get_invite_preview RPC.
 * Callable safely by prospective students before installing or signing in.
 */
export async function fetchInvitation(token: string): Promise<InvitationState> {
  const clean = token.trim();
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(clean)) {
    return { status: "invalid" };
  }

  // Preserve token in localStorage for deferred deep linking after installation
  try {
    if (typeof window !== "undefined" && window.localStorage) {
      window.localStorage.setItem("studyup_pending_invite_token", clean);
    }
  } catch (_) {}

  try {
    const config = await getClientConfig();
    const res = await fetch(`${config.supabaseUrl}/rest/v1/rpc/get_invite_preview`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: config.supabaseAnonKey,
        Authorization: `Bearer ${config.supabaseAnonKey}`,
      },
      body: JSON.stringify({ p_token: clean }),
    });

    if (!res.ok) {
      return { status: "invalid" };
    }

    const data = await res.json();
    const status = data?.status;

    if (status === "valid") {
      return {
        status: "ready",
        inviter: {
          displayName: data.inviter_name || "A friend",
          avatarUrl: data.inviter_avatar || undefined,
        },
      };
    } else if (status === "expired") {
      return { status: "expired" };
    } else if (status === "used") {
      return { status: "already_accepted" };
    } else {
      return { status: "invalid" };
    }
  } catch (_) {
    // Mock tokens fallback for local preview/testing without internet
    if (clean === "valid-demo-token") {
      return { status: "ready", inviter: { displayName: "Demo Friend" } };
    }
    if (clean === "expired-demo-token") return { status: "expired" };
    if (clean === "used-demo-token") return { status: "already_accepted" };
    throw new Error("Could not reach invitation service.");
  }
}

/**
 * Directs user to open the installed app or explains that friendship creation requires StudyUP account.
 */
export async function acceptInvitation(token: string): Promise<void> {
  const clean = token.trim();
  if (!clean) throw new NotConnectedError("Invalid invitation token.");

  // Preserve token
  try {
    if (typeof window !== "undefined" && window.localStorage) {
      window.localStorage.setItem("studyup_pending_invite_token", clean);
    }
  } catch (_) {}

  // Attempt to open deep link on mobile/desktop
  if (typeof window !== "undefined") {
    const deepLink = `studyup://invite/${encodeURIComponent(clean)}`;
    window.location.href = deepLink;
  }
}
