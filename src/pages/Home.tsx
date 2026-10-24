import { Link } from "react-router-dom";
import DownloadCTA from "../components/DownloadCTA";
import { CommunityPreview, ProductPreview } from "../components/Previews";
import { useTitle } from "../components/Layout";

// TODO(features): Confirm every item against what the real app does before publishing.
const features = [
  { t: "Study-time tracking", d: "Log each study session and see exactly where your hours go." },
  { t: "Progress insights", d: "Look back across days and weeks to see how your effort adds up." },
  { t: "Consistency", d: "Spot your habits and keep your streak of regular sessions going." },
  { t: "Goals", d: "Set a target for your study time and watch yourself move toward it." },
  { t: "Studying with friends", d: "Connect with friends and compare weekly progress, where you choose to share." },
];
const steps = [
  { t: "Start a session", d: "Begin tracking when you sit down to study." },
  { t: "See your progress", d: "Your sessions turn into clear summaries of your time." },
  { t: "Keep it going", d: "Build a routine you can see, and adjust as you learn." },
];

export default function Home() {
  useTitle("StudyUP: make study progress visible");
  return (
    <>
      <section className="hero">
        <div className="wrap hero-in">
          <div>
            <h1 className="display">Make your study progress visible.</h1>
            <p className="lead">StudyUP tracks your study sessions and shows how your effort adds up, so consistent habits are easier to build and keep.</p>
            <div className="row">
              <DownloadCTA />
              <Link className="btn btn-ghost" to="/#features">See how it works</Link>
            </div>
          </div>
          <ProductPreview />
        </div>
      </section>

      <section id="features" className="section">
        <div className="wrap">
          <h2>What StudyUP helps you do</h2>
          <div className="grid">
            {features.map((f) => (
              <article key={f.t} className="card">
                <h3>{f.t}</h3>
                <p className="muted">{f.d}</p>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section alt" aria-labelledby="how">
        <div className="wrap">
          <h2 id="how">How it works</h2>
          <ol className="steps">
            {steps.map((s) => (
              <li key={s.t}><h3>{s.t}</h3><p className="muted">{s.d}</p></li>
            ))}
          </ol>
        </div>
      </section>

      <section className="section">
        <div className="wrap split">
          <div>
            <h2>Study better, together</h2>
            <p className="lead">Invite a friend, connect, and compare your weekly study progress. Friends see progress summaries, not your individual sessions.</p>
            {/* TODO(community): Confirm this privacy statement matches the real backend rules before publishing. */}
          </div>
          <CommunityPreview />
        </div>
      </section>

      <section className="cta">
        <div className="wrap cta-in">
          <h2>Ready to see your progress?</h2>
          <p>Get StudyUP and start your first session.</p>
          <DownloadCTA variant="light" />
        </div>
      </section>
    </>
  );
}
