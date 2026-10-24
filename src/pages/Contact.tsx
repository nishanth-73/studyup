import { FormEvent, useState } from "react";
import { useTitle } from "../components/Layout";
import { submitContact } from "../services/contact";

type Status = "idle" | "sending" | "notConnected" | "error";
const emailOk = (v: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);

export default function Contact() {
  useTitle("Contact · StudyUP");
  const [status, setStatus] = useState<Status>("idle");
  const [errors, setErrors] = useState<Record<string, string>>({});

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const v = { name: String(f.get("name") ?? "").trim(), email: String(f.get("email") ?? "").trim(), message: String(f.get("message") ?? "").trim() };
    const errs: Record<string, string> = {};
    if (!v.name) errs.name = "Enter your name.";
    if (!emailOk(v.email)) errs.email = "Enter a valid email address.";
    if (v.message.length < 10) errs.message = "Write at least 10 characters.";
    setErrors(errs);
    if (Object.keys(errs).length) return;
    setStatus("sending");
    try {
      const r = await submitContact(v);
      setStatus(r.delivered ? "idle" : "notConnected"); // TODO(contact): add a real success state once delivery is confirmed.
    } catch { setStatus("error"); }
  }

  return (
    <div className="wrap page narrow">
      <h1>Contact</h1>
      <p className="lead">Questions or feedback? Write to us below.</p>
      <form onSubmit={onSubmit} noValidate className="card form">
        {(["name", "email", "message"] as const).map((k) => (
          <div className="field" key={k}>
            <label htmlFor={k}>{k === "name" ? "Name" : k === "email" ? "Email" : "Message"}</label>
            {k === "message"
              ? <textarea id={k} name={k} rows={5} aria-invalid={!!errors[k]} aria-describedby={errors[k] ? `${k}-e` : undefined} />
              : <input id={k} name={k} type={k === "email" ? "email" : "text"} autoComplete={k} aria-invalid={!!errors[k]} aria-describedby={errors[k] ? `${k}-e` : undefined} />}
            {errors[k] && <span className="err" id={`${k}-e`}>{errors[k]}</span>}
          </div>
        ))}
        <button className="btn btn-primary" disabled={status === "sending"}>{status === "sending" ? "Sending…" : "Send message"}</button>
        <div role="status" aria-live="polite">
          {status === "notConnected" && <p className="note">Your message is valid, but sending isn’t connected yet in this preview. Nothing was sent.</p>}
          {status === "error" && <p className="err">Something went wrong. Check your connection and try again.</p>}
        </div>
      </form>
    </div>
  );
}
