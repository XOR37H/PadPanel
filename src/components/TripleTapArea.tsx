import React, { useState, useRef, useEffect } from "react";
import { Settings } from "lucide-react";

interface TripleTapAreaProps {
  onTrigger: () => void;
}

export const TripleTapArea: React.FC<TripleTapAreaProps> = ({ onTrigger }) => {
  const [tapCount, setTapCount] = useState<number>(0);
  const timerRef = useRef<number | null>(null);

  const handleTap = (e: React.MouseEvent | React.TouchEvent) => {
    e.stopPropagation();

    // Clear existing timer
    if (timerRef.current) {
      window.clearTimeout(timerRef.current);
    }

    const nextCount = tapCount + 1;

    if (nextCount >= 3) {
      setTapCount(0);
      onTrigger();
    } else {
      setTapCount(nextCount);
      timerRef.current = window.setTimeout(() => {
        setTapCount(0);
      }, 700);
    }
  };

  // Keyboard shortcut: Press 'S' to open settings easily on laptop / desktop
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        (e.key === "s" || e.key === "S") &&
        !["INPUT", "TEXTAREA"].includes((e.target as HTMLElement)?.tagName)
      ) {
        onTrigger();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onTrigger]);

  return (
    <div className="fixed top-2 right-2 z-30 select-none">
      <button
        type="button"
        onClick={handleTap}
        title="Triple-tap to open PadPanel Settings (or press 'S')"
        className="w-12 h-12 rounded-full bg-white/10 hover:bg-white/20 active:scale-90 transition flex items-center justify-center cursor-pointer border border-white/15 backdrop-blur-sm relative group focus:outline-none"
      >
        <Settings className="w-4 h-4 text-white/40 group-hover:text-white/80 transition-colors" />

        {/* Tap counter hint when user is tapping */}
        {tapCount > 0 && (
          <span className="absolute -bottom-2 -left-2 w-5 h-5 rounded-full bg-indigo-500 text-[10px] font-bold text-white flex items-center justify-center shadow-lg animate-bounce">
            {tapCount}
          </span>
        )}
      </button>
    </div>
  );
};
