// Audio utility for PadPanel voice satellite sounds with iOS 15 WebAudio unlock

class SoundPlayer {
  private audioCtx: AudioContext | null = null;
  private onAudio: HTMLAudioElement | null = null;
  private offAudio: HTMLAudioElement | null = null;
  private isUnlocked: boolean = false;

  constructor() {
    if (typeof window !== "undefined") {
      this.onAudio = new Audio("/sounds/Speech_On.wav");
      this.offAudio = new Audio("/sounds/Speech_Off.wav");

      // Auto-unlock on first user touch/click (essential for iOS 15 Safari)
      const unlockHandler = () => {
        this.unlockAudio();
        window.removeEventListener("touchstart", unlockHandler);
        window.removeEventListener("touchend", unlockHandler);
        window.removeEventListener("click", unlockHandler);
      };
      window.addEventListener("touchstart", unlockHandler, { passive: true });
      window.addEventListener("touchend", unlockHandler, { passive: true });
      window.addEventListener("click", unlockHandler, { passive: true });
    }
  }

  public unlockAudio() {
    if (this.isUnlocked) return;
    try {
      const ctx = this.getAudioContext();
      if (ctx.state === "suspended") {
        ctx.resume().then(() => {
          this.isUnlocked = true;
        }).catch(() => {});
      } else {
        this.isUnlocked = true;
      }
    } catch {
      // Ignore
    }
  }

  private getAudioContext(): AudioContext {
    if (!this.audioCtx) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
      this.audioCtx = new AudioCtx();
    }
    if (this.audioCtx.state === "suspended") {
      this.audioCtx.resume().catch(() => {});
    }
    return this.audioCtx;
  }

  // Fallback synthetic chime if wav cannot be played
  private playSynthesizedChime(type: "on" | "off") {
    try {
      const ctx = this.getAudioContext();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      const now = ctx.currentTime;

      if (type === "on") {
        // High ascending tone
        osc.frequency.setValueAtTime(587.33, now); // D5
        osc.frequency.exponentialRampToValueAtTime(880, now + 0.15); // A5
        gain.gain.setValueAtTime(0.3, now);
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.25);
        osc.start(now);
        osc.stop(now + 0.25);
      } else {
        // Descending soft tone
        osc.frequency.setValueAtTime(783.99, now); // G5
        osc.frequency.exponentialRampToValueAtTime(440, now + 0.18); // A4
        gain.gain.setValueAtTime(0.3, now);
        gain.gain.exponentialRampToValueAtTime(0.01, now + 0.25);
        osc.start(now);
        osc.stop(now + 0.25);
      }

      osc.connect(gain);
      gain.connect(ctx.destination);
    } catch (e) {
      console.warn("Synthesized chime error:", e);
    }
  }

  public playSpeechOn() {
    this.unlockAudio();
    if (this.onAudio) {
      this.onAudio.currentTime = 0;
      this.onAudio.play().catch(() => {
        this.playSynthesizedChime("on");
      });
    } else {
      this.playSynthesizedChime("on");
    }
  }

  public playSpeechOff() {
    this.unlockAudio();
    if (this.offAudio) {
      this.offAudio.currentTime = 0;
      this.offAudio.play().catch(() => {
        this.playSynthesizedChime("off");
      });
    } else {
      this.playSynthesizedChime("off");
    }
  }
}

export const soundPlayer = new SoundPlayer();
