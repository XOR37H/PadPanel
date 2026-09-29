import React, { useState } from "react";
import { Lock, X, ShieldCheck, KeyRound, Eye, EyeOff } from "lucide-react";

interface DeviceAuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAuthenticated: () => void;
  expectedUsername: string;
  expectedPassword: string;
}

export const DeviceAuthModal: React.FC<DeviceAuthModalProps> = ({
  isOpen,
  onClose,
  onAuthenticated,
  expectedUsername,
  expectedPassword,
}) => {
  const [username, setUsername] = useState<string>(expectedUsername || "admin");
  const [password, setPassword] = useState<string>("");
  const [showPassword, setShowPassword] = useState<boolean>(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  React.useEffect(() => {
    if (isOpen) {
      setUsername(expectedUsername || "admin");
      setPassword("");
      setErrorMsg(null);
      setShowPassword(false);
    }
  }, [isOpen, expectedUsername]);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    // Check credentials
    const isUserValid = !expectedUsername || username.trim().toLowerCase() === expectedUsername.trim().toLowerCase();
    const isPassValid = password === expectedPassword;

    if (isUserValid && isPassValid) {
      setErrorMsg(null);
      onAuthenticated();
    } else {
      setErrorMsg("Incorrect username or password. Access denied.");
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in duration-200">
      <div className="relative w-full max-w-sm bg-slate-900 border border-slate-700/80 rounded-3xl shadow-2xl p-6 text-slate-100 font-sans">
        
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute top-4 right-4 p-1.5 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800 transition"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Icon & Title */}
        <div className="flex flex-col items-center text-center mb-6">
          <div className="w-12 h-12 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center mb-3">
            <Lock className="w-6 h-6 text-indigo-400" />
          </div>
          <h2 className="text-lg font-bold text-white tracking-tight">Kiosk Settings Locked</h2>
          <p className="text-xs text-slate-400 mt-1">
            Enter device administrator credentials to unlock configuration.
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Username</label>
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="admin"
              className="w-full px-3.5 py-2.5 rounded-xl bg-slate-950 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Password</label>
            <div className="relative">
              <input
                type={showPassword ? "text" : "password"}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Enter password..."
                autoFocus
                className="w-full px-3.5 py-2.5 pr-10 rounded-xl bg-slate-950 border border-slate-700 text-xs text-white focus:outline-none focus:border-indigo-500"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          {errorMsg && (
            <div className="p-2.5 rounded-xl bg-rose-500/15 border border-rose-500/30 text-rose-300 text-xs text-center">
              {errorMsg}
            </div>
          )}

          <div className="flex space-x-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-medium transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="flex-1 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-lg shadow-indigo-600/30 transition flex items-center justify-center space-x-1.5"
            >
              <KeyRound className="w-3.5 h-3.5" />
              <span>Unlock</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
