/**
 * Central site configuration. EDIT THIS FILE to connect real values.
 */
export const siteConfig = {
  name: "StudyUP",
  android: {
    /**
     * TODO(download): Put the real Android download URL here (https only), e.g. a Play Store listing or direct APK download.
     * When left empty, clicking 'Download StudyUP' will display a polished release notice modal.
     */
    downloadUrl: "",
    // TODO(deep-link): Add Android App Links config (assetlinks.json + intent filters) before routing /invite/:token into the app.
  },
  // TODO(contact): Add a real, verified contact address when you have one. Never hardcode a guess.
  contactEmail: "",
};

export const isDownloadAvailable = (): boolean =>
  typeof siteConfig.android.downloadUrl === "string" &&
  /^https:\/\/\S+$/.test(siteConfig.android.downloadUrl.trim());
