import { useTitle } from "../components/Layout";

const Need = () => <span className="tag warn">Needs confirmation</span>;

/** TODO(legal): This is placeholder structure, not legal advice. Review every section with a qualified professional against the real app before publishing. */
export default function Privacy() {
  useTitle("Privacy Policy · StudyUP");
  return (
    <div className="wrap page narrow">
      <h1>Privacy Policy</h1>
      <p className="banner" role="note">Draft placeholder. This text is not final and is not legal advice. Items marked “Needs confirmation” must be verified before publication.</p>
      <p className="muted">Last updated: <Need /></p>
      <h2>Who we are</h2><p>Legal entity name and contact details: <Need /></p>
      <h2>Information we collect</h2><p>Describe the account, profile, and study-session information the app actually stores. <Need /></p>
      <h2>How we use information</h2><p>Describe real purposes, such as showing your progress. <Need /></p>
      <h2>Sharing with friends</h2><p>Describe what progress summaries friends can see and what stays private. <Need /></p>
      <h2>Service providers and storage</h2><p>List the real providers that process or store data, and where. <Need /></p>
      <h2>Retention and your choices</h2><p>Describe retention, deletion, and access options. <Need /></p>
      <h2>Contact</h2><p>Privacy contact: <Need /></p>
    </div>
  );
}
