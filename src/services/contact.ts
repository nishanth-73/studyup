export type ContactPayload = { name: string; email: string; message: string };
export type ContactResult = { delivered: false; reason: "not_connected" };

/**
 * MOCK submission handler. Nothing is sent anywhere.
 * TODO(contact): Replace with a real email service or backend call. Only return delivered: true when the service confirms it.
 */
export async function submitContact(_payload: ContactPayload): Promise<ContactResult> {
  await new Promise((r) => setTimeout(r, 700));
  return { delivered: false, reason: "not_connected" };
}
