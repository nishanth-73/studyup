/**
 * ILLUSTRATIVE previews built for the website.
 * Matches StudyUP's calm dark palette and Community podium tokens:
 * - 1st: Green (#8BC48A)
 * - 2nd: Blue (#7DD3E8)
 * - 3rd: Pink (#FF8FA8)
 */
const week = [
  { d: "Mon", h: 62 },
  { d: "Tue", h: 80 },
  { d: "Wed", h: 45 },
  { d: "Thu", h: 95 },
  { d: "Fri", h: 70 },
  { d: "Sat", h: 35 },
  { d: "Sun", h: 60 },
];

export function ProductPreview() {
  return (
    <figure className="preview" aria-label="Illustrative preview of the StudyUP app">
      <div className="pv-top">
        <span className="pv-title">This week</span>
        <span className="tag">Illustrative preview</span>
      </div>
      <div className="bars" role="img" aria-label="Sample bar chart of study time across a week">
        {week.map((b) => (
          <div className="bar-col" key={b.d}>
            <div className="bar" style={{ height: `${b.h}%` }} />
            <span>{b.d}</span>
          </div>
        ))}
      </div>
      <div className="pv-row">
        <div className="pv-card">
          <span className="muted small">Sample streak</span>
          <strong>6 days</strong>
        </div>
        <div className="pv-card">
          <span className="muted small">Sample weekly goal</span>
          <div className="meter" aria-hidden="true" style={{ marginTop: "0.4rem" }}>
            <i style={{ width: "75%", background: "var(--cta)" }} />
          </div>
        </div>
      </div>
      <figcaption className="sr">Sample data for illustration only.</figcaption>
    </figure>
  );
}

/** Demo-only data. Clearly separate from real user data. */
const demo = [
  { n: "Alex", rank: "#1", v: 88, color: "var(--green)" },
  { n: "You", rank: "#2", v: 74, color: "var(--blue)" },
  { n: "Sam", rank: "#3", v: 58, color: "var(--pink)" },
  { n: "Jordan", rank: "#4", v: 42, color: "var(--cta)" },
];

export function CommunityPreview() {
  return (
    <figure className="preview">
      <div className="pv-top">
        <span className="pv-title">Weekly comparison</span>
        <span className="tag">Demo data</span>
      </div>
      <ul className="lb">
        {demo.map((r) => (
          <li key={r.n} className={r.n === "You" ? "me" : ""}>
            <span style={{ color: r.color, fontWeight: 700 }}>
              {r.rank} {r.n}
            </span>
            <div className="meter" aria-hidden="true">
              <i style={{ width: `${r.v}%`, background: r.color }} />
            </div>
            <span className="muted small">{r.v}%</span>
          </li>
        ))}
      </ul>
      <figcaption className="small muted">
        Illustrative friend comparison matching StudyUP's community design.
      </figcaption>
    </figure>
  );
}
