import React, { useState } from "react";
import { HomeAssistantDemoView } from "./HomeAssistantDemoView";
import { ExternalLink, RefreshCw, AlertTriangle } from "lucide-react";

interface KioskWebViewProps {
  url: string | null;
  isActive: boolean;
  onOpenSettings: () => void;
  onActivity: () => void;
}

export const KioskWebView: React.FC<KioskWebViewProps> = ({
  url,
  isActive,
  onOpenSettings,
  onActivity,
}) => {
  const [iframeError, setIframeError] = useState<boolean>(false);
  const [reloadKey, setReloadKey] = useState<number>(0);

  // If no URL or blank, render the built-in Home Assistant demo dashboard
  if (!url || url.trim() === "") {
    return <HomeAssistantDemoView onOpenSettings={onOpenSettings} />;
  }

  const handleReload = () => {
    setIframeError(false);
    setReloadKey((prev) => prev + 1);
  };

  return (
    <div
      className="relative w-full h-full bg-black select-none overflow-hidden"
      onClick={onActivity}
      onTouchStart={onActivity}
    >
      <iframe
        key={reloadKey}
        src={url}
        title="UltraKiosk Web View"
        className="w-full h-full border-0 bg-black"
        allow="camera; microphone; display-capture; fullscreen; geolocation"
        sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-modals"
        onError={() => setIframeError(true)}
      />

      {/* Fallback warning overlay if iframe fails to load or blocked by X-Frame-Options */}
      {iframeError && (
        <div className="absolute inset-0 bg-slate-950/95 flex flex-col items-center justify-center p-6 text-center text-white z-20">
          <div className="w-14 h-14 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex items-center justify-center mb-4">
            <AlertTriangle className="w-8 h-8 text-amber-400" />
          </div>
          <h2 className="text-xl font-bold mb-2">Unable to load dashboard directly inside iframe</h2>
          <p className="text-sm text-slate-300 max-w-md mb-4">
            The target site (<code>{url}</code>) may restrict iframe embedding via <span className="font-mono text-amber-300">X-Frame-Options</span> or CSP headers.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <button
              onClick={handleReload}
              className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/20 text-sm font-medium flex items-center space-x-2 border border-white/20"
            >
              <RefreshCw className="w-4 h-4" />
              <span>Retry</span>
            </button>
            <a
              href={url}
              target="_blank"
              rel="noopener noreferrer"
              className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-sm font-medium flex items-center space-x-2 text-white"
            >
              <span>Open in new tab</span>
              <ExternalLink className="w-4 h-4" />
            </a>
            <button
              onClick={onOpenSettings}
              className="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/20 text-sm font-medium border border-white/20"
            >
              Edit URL in Settings
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
