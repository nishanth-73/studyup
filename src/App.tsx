import { Route, Routes, Link } from "react-router-dom";
import Layout, { useTitle } from "./components/Layout";
import Home from "./pages/Home";
import About from "./pages/About";
import Contact from "./pages/Contact";
import Privacy from "./pages/Privacy";
import Invite from "./pages/Invite";

function NotFound() {
  useTitle("Page not found · StudyUP");
  return (
    <div className="wrap page">
      <h1>Page not found</h1>
      <p>
        <Link to="/">Back to the home page</Link>
      </p>
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      {/* Invitation routes are outside Layout so they never render the landing page chrome. */}
      <Route path="/invite/:token" element={<Invite />} />
      <Route path="/i/:token" element={<Invite />} />
      <Route element={<Layout />}>
        <Route path="/" element={<Home />} />
        <Route path="/about" element={<About />} />
        <Route path="/contact" element={<Contact />} />
        <Route path="/privacy" element={<Privacy />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  );
}
