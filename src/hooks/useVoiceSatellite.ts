import { useState, useEffect, useRef, useCallback } from "react";
import { soundPlayer } from "../utils/audio";
import { UltraKioskSettings } from "../types/settings";

interface VoiceSatelliteOptions {
  settings: UltraKioskSettings;
  onVoiceCommand?: (text: string) => void;
}

export function useVoiceSatellite({ settings, onVoiceCommand }: VoiceSatelliteOptions) {
  const [isListening, setIsListening] = useState<boolean>(false);
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [audioLevel, setAudioLevel] = useState<number>(0);
  const [micActive, setMicActive] = useState<boolean>(false);
  const [lastSpokenText, setLastSpokenText] = useState<string>("");
  const [satelliteStatus, setSatelliteStatus] = useState<string>("Standby");

  const streamRef = useRef<MediaStream | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animFrameRef = useRef<number | null>(null);
  const timeoutRef = useRef<number | null>(null);

  // Stop microphone stream
  const stopMic = useCallback(() => {
    if (animFrameRef.current) {
      cancelAnimationFrame(animFrameRef.current);
      animFrameRef.current = null;
    }
    if (timeoutRef.current) {
      window.clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }
    if (audioContextRef.current && audioContextRef.current.state !== "closed") {
      audioContextRef.current.close().catch(() => {});
      audioContextRef.current = null;
    }
    setMicActive(false);
    setIsListening(false);
    setIsProcessing(false);
    setAudioLevel(0);
    setSatelliteStatus("Voice Satellite Off");
  }, []);

  // Monitor audio levels
  const monitorAudio = useCallback(() => {
    if (!analyserRef.current) return;
    const dataArray = new Uint8Array(analyserRef.current.frequencyBinCount);
    analyserRef.current.getByteFrequencyData(dataArray);

    let sum = 0;
    for (let i = 0; i < dataArray.length; i++) {
      sum += dataArray[i];
    }
    const avg = sum / dataArray.length;
    const normalized = Math.min(100, Math.round((avg / 128) * 100));
    setAudioLevel(normalized);

    // Audio reactive loop
    animFrameRef.current = requestAnimationFrame(monitorAudio);
  }, []);

  // Start microphone
  const startMic = useCallback(async () => {
    if (!settings.enableVoiceActivation) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: settings.voiceSampleRate,
          echoCancellation: true,
          noiseSuppression: true,
        },
      });

      streamRef.current = stream;
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      const ctx = new AudioCtx({ sampleRate: settings.voiceSampleRate });
      audioContextRef.current = ctx;

      const source = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 256;
      source.connect(analyser);
      analyserRef.current = analyser;

      setMicActive(true);
      setSatelliteStatus("Listening for wake word (Porcupine)");
      monitorAudio();
    } catch (e) {
      console.warn("Could not access microphone for Voice Satellite:", e);
      setSatelliteStatus("Microphone unavailable (simulation enabled)");
      setMicActive(false);
    }
  }, [settings.enableVoiceActivation, settings.voiceSampleRate, monitorAudio]);

  useEffect(() => {
    if (settings.enableVoiceActivation) {
      startMic();
    } else {
      stopMic();
    }
    return () => {
      stopMic();
    };
  }, [settings.enableVoiceActivation, startMic, stopMic]);

  // Trigger assistant wake
  const triggerWakeWord = useCallback((customText?: string) => {
    soundPlayer.playSpeechOn();
    setIsListening(true);
    setSatelliteStatus("Assistant Activated — Listening...");

    // Simulated speech command recognition after timeout
    const waitTime = Math.max(2, settings.voiceTimeout) * 1000;
    if (timeoutRef.current) {
      window.clearTimeout(timeoutRef.current);
    }

    timeoutRef.current = window.setTimeout(() => {
      setIsListening(false);
      setIsProcessing(true);
      setSatelliteStatus("Processing with Home Assistant Voice Pipeline...");

      setTimeout(() => {
        const text = customText || "Turn on Living Room Accent Lights";
        setLastSpokenText(text);
        soundPlayer.playSpeechOff();
        setIsProcessing(false);
        setSatelliteStatus(`Command executed: "${text}"`);
        onVoiceCommand?.(text);

        setTimeout(() => {
          setSatelliteStatus(settings.enableVoiceActivation ? "Listening for wake word" : "Standby");
        }, 4000);
      }, 1200);
    }, waitTime);
  }, [settings.voiceTimeout, settings.enableVoiceActivation, onVoiceCommand]);

  return {
    isListening,
    isProcessing,
    micActive,
    audioLevel,
    satelliteStatus,
    lastSpokenText,
    triggerWakeWord,
    startMic,
    stopMic,
  };
}
