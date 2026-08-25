/**
 * Status page layout — minimal, no sidebar, no dashboard chrome.
 * Mirrors the root layout's ThemeProvider + RuntimeI18nProvider so
 * dark/light mode works identically.
 */
import { ThemeProvider } from "@/shared/components/ThemeProvider";
import { RuntimeI18nProvider } from "@/i18n/RuntimeI18nProvider";

export const metadata = {
  title: "System Status — 9Router",
  description: "Live status and uptime for 9Router AI routing infrastructure.",
  robots: "noindex, nofollow",
};

export default function StatusLayout({ children }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `if(document.fonts&&document.fonts.ready){document.fonts.ready.then(function(){document.documentElement.classList.add('fonts-loaded')})}else{document.documentElement.classList.add('fonts-loaded')}`,
          }}
        />
      </head>
      <body className="font-sans antialiased bg-bg text-text-main transition-colors duration-300">
        <ThemeProvider>
          <RuntimeI18nProvider>{children}</RuntimeI18nProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
