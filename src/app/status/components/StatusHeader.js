/**
 * Header component — compact top bar with logo, title, and theme toggle.
 */
"use client";

import ThemeToggle from "@/shared/components/ThemeToggle";

export default function StatusHeader() {
  return (
    <header className="flex items-center justify-between px-6 py-4 border-b border-border-subtle">
      <div className="flex items-center gap-3">
        {/* Logo mark */}
        <div className="w-7 h-7 rounded-lg bg-primary flex items-center justify-center text-bg text-sm font-bold select-none">
          9
        </div>
        <div>
          <h1 className="text-sm font-semibold leading-none text-text-main">
            9Router Status
          </h1>
          <p className="text-xs text-text-subtle mt-0.5">
            ai.9router.app
          </p>
        </div>
      </div>
      <ThemeToggle variant="icon" />
    </header>
  );
}
