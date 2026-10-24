import { useState, useEffect } from "react";
import { isDownloadAvailable, siteConfig } from "../config/site";
import { LogoMark } from "./Logo";

type Props = {
  variant?: "primary" | "secondary" | "light" | "ghost";
  compact?: boolean;
  label?: string;
};

export default function DownloadCTA({
  variant = "primary",
  compact = false,
  label = "Download StudyUP",
}: Props) {
  const [modalOpen, setModalOpen] = useState(false);
  const cls = `btn btn-${variant}${compact ? " btn-sm" : ""}`;

  useEffect(() => {
    if (!modalOpen) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") setModalOpen(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [modalOpen]);

  if (isDownloadAvailable()) {
    return (
      <a
        className={cls}
        href={siteConfig.android.downloadUrl}
        rel="noopener noreferrer"
      >
        {label}
      </a>
    );
  }

  return (
    <>
      <button
        type="button"
        className={cls}
        onClick={() => setModalOpen(true)}
        aria-haspopup="dialog"
      >
        {label}
      </button>

      {modalOpen && (
        <div
          className="modal-backdrop"
          onClick={() => setModalOpen(false)}
          role="presentation"
        >
          <div
            className="modal-card"
            role="dialog"
            aria-modal="true"
            aria-labelledby="download-modal-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="modal-header">
              <LogoMark size={40} />
              <div>
                <h3 id="download-modal-title" style={{ margin: 0 }}>
                  Download StudyUP
                </h3>
                <span className="muted small">Android Release</span>
              </div>
            </div>
            <p className="modal-body">
              The StudyUP Android release is being finalized. Once published,
              the direct download and store link will be available right here.
            </p>
            <div className="modal-actions">
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => setModalOpen(false)}
                autoFocus
              >
                Got it
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
