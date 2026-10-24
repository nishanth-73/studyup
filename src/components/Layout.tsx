import { useEffect } from "react";
import { Link, NavLink, Outlet, useLocation } from "react-router-dom";
import { Logo } from "./Logo";
import DownloadCTA from "./DownloadCTA";

export function useTitle(title: string) {
  useEffect(() => { document.title = title; }, [title]);
}

function ScrollManager() {
  const { pathname, hash } = useLocation();
  useEffect(() => {
    if (hash) document.getElementById(hash.slice(1))?.scrollIntoView();
    else window.scrollTo(0, 0);
  }, [pathname, hash]);
  return null;
}

export function Navbar() {
  return (
    <header className="nav">
      <div className="wrap nav-in">
        <Logo />
        <nav aria-label="Main" className="nav-links">
          <Link to="/#features">Features</Link>
          <NavLink to="/about">About</NavLink>
          <NavLink to="/contact">Contact</NavLink>
        </nav>
        <DownloadCTA compact />
      </div>
    </header>
  );
}

export function Footer() {
  return (
    <footer className="footer">
      <div className="wrap foot-in">
        <div>
          <Logo />
          <p className="muted small">Make study progress visible.</p>
        </div>
        <nav aria-label="Footer" className="foot-links">
          <Link to="/#features">Features</Link>
          <Link to="/about">About</Link>
          <Link to="/contact">Contact</Link>
          <Link to="/privacy">Privacy Policy</Link>
          {/* TODO(terms): Add a Terms link once terms exist. */}
        </nav>
      </div>
      <div className="wrap small muted foot-copy">© {new Date().getFullYear()} StudyUP</div>
    </footer>
  );
}

export default function Layout() {
  return (
    <>
      <a href="#main" className="skip">Skip to content</a>
      <ScrollManager />
      <Navbar />
      <main id="main"><Outlet /></main>
      <Footer />
    </>
  );
}
