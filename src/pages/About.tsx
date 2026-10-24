import { useTitle } from "../components/Layout";
export default function About() {
  useTitle("About · StudyUP");
  return (
    <div className="wrap page">
      <h1>About StudyUP</h1>
      <p className="lead">StudyUP exists to help students track their study sessions, understand their progress, and build better study habits.</p>
      <h2>Why we’re building it</h2>
      <p>{/* TODO(copy): Replace with your real story. */}Studying is easier to stick with when you can see it. StudyUP turns your sessions into a clear picture of your time and consistency.</p>
      <h2>Who’s behind it</h2>
      <p className="placeholder">{/* TODO(copy): Add founder or team details only when you’re ready to share them. */}Team details will go here.</p>
    </div>
  );
}
