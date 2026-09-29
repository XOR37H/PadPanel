import { useEffect, useRef, useState, useCallback } from "react";
import { WakeupMethod } from "../types/settings";

interface FaceDetectionOptions {
  enabled: boolean;
  interval: number; // in seconds
  wakeupMethod?: WakeupMethod; // "face" | "motion"
  motionSensitivity?: number; // 0.02 (high) to 0.25 (low), default 0.08
  showDebugInfo?: boolean;
  onFaceDetected: () => void;
}

export function useFaceDetection({
  enabled,
  interval,
  wakeupMethod = "face",
  motionSensitivity = 0.08,
  showDebugInfo = true,
  onFaceDetected,
}: FaceDetectionOptions) {
  const [isDetecting, setIsDetecting] = useState<boolean>(false);
  const [cameraActive, setCameraActive] = useState<boolean>(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [motionLevel, setMotionLevel] = useState<number>(0);
  const [detectedType, setDetectedType] = useState<"face" | "motion" | null>(null);
  const [lastDetectionTime, setLastDetectionTime] = useState<Date | null>(null);
  const [processedFramesCount, setProcessedFramesCount] = useState<number>(0);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const intervalIdRef = useRef<number | null>(null);
  const prevImageDataRef = useRef<Uint8ClampedArray | null>(null);

  // Stop camera cleanly
  const stopCamera = useCallback(() => {
    if (intervalIdRef.current) {
      window.clearInterval(intervalIdRef.current);
      intervalIdRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }
    if (videoRef.current) {
      videoRef.current.srcObject = null;
    }
    setCameraActive(false);
    setIsDetecting(false);
    prevImageDataRef.current = null;
  }, []);

  // Frame processing step: checks for face or motion
  const processFrame = useCallback(async () => {
    if (!videoRef.current || !canvasRef.current || videoRef.current.readyState < 2) return;

    const video = videoRef.current;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (!ctx) return;

    const width = 64; // Low res for fast, energy-efficient iPad CPU processing
    const height = 48;
    canvas.width = width;
    canvas.height = height;

    try {
      ctx.drawImage(video, 0, 0, width, height);
      setProcessedFramesCount((c) => (c + 1) % 10000);

      // If wakeupMethod is "face", try browser native FaceDetector if supported
      if (wakeupMethod === "face") {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const FaceDetectorAPI = (window as any).FaceDetector;
        if (FaceDetectorAPI) {
          try {
            const detector = new FaceDetectorAPI({ fastMode: true, maxDetectedFaces: 2 });
            const faces = await detector.detect(canvas);
            if (faces && faces.length > 0) {
              setDetectedType("face");
              setLastDetectionTime(new Date());
              onFaceDetected();
              return;
            }
          } catch {
            // Fall through to optical motion detection
          }
        }
      }

      // Optical motion calculation
      const currentData = ctx.getImageData(0, 0, width, height).data;
      if (prevImageDataRef.current) {
        let diffCount = 0;
        const totalPixels = width * height;
        // Motion threshold per color channel
        const colorThreshold = 40;
        for (let i = 0; i < currentData.length; i += 4) {
          const rDiff = Math.abs(currentData[i] - prevImageDataRef.current[i]);
          const gDiff = Math.abs(currentData[i + 1] - prevImageDataRef.current[i + 1]);
          const bDiff = Math.abs(currentData[i + 2] - prevImageDataRef.current[i + 2]);
          if (rDiff + gDiff + bDiff > colorThreshold) {
            diffCount++;
          }
        }

        const deltaRatio = diffCount / totalPixels;
        const deltaPercentage = Math.min(100, Math.round(deltaRatio * 100));
        setMotionLevel(deltaPercentage);

        // Calculate dynamic threshold based on motionSensitivity (e.g. 0.08 = 8% pixel delta)
        const triggerThreshold = Math.max(0.015, motionSensitivity);
        if (deltaRatio >= triggerThreshold) {
          setDetectedType(wakeupMethod === "face" ? "face" : "motion");
          setLastDetectionTime(new Date());
          onFaceDetected();
        }
      }

      prevImageDataRef.current = new Uint8ClampedArray(currentData);
    } catch {
      // Ignore cross-origin drawing exceptions
    }
  }, [wakeupMethod, motionSensitivity, onFaceDetected]);

  // Start camera when enabled
  const startCamera = useCallback(async () => {
    if (!enabled) return;
    try {
      setCameraError(null);
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          width: { ideal: 320 },
          height: { ideal: 240 },
          facingMode: "user",
        },
        audio: false,
      });

      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play().catch(() => {});
      }

      setCameraActive(true);
      setIsDetecting(true);

      const intervalMs = Math.max(100, interval * 1000);
      intervalIdRef.current = window.setInterval(processFrame, intervalMs);
    } catch (err: unknown) {
      setCameraError(err instanceof Error ? err.message : "Camera access denied or unavailable");
      setCameraActive(false);
      setIsDetecting(false);
    }
  }, [enabled, interval, processFrame]);

  // Restart camera lifecycle
  useEffect(() => {
    if (enabled) {
      startCamera();
    } else {
      stopCamera();
    }
    return () => {
      stopCamera();
    };
  }, [enabled, interval, startCamera, stopCamera]);

  // Manual trigger for testing
  const simulateDetection = useCallback(() => {
    setMotionLevel(28);
    setDetectedType(wakeupMethod);
    setLastDetectionTime(new Date());
    onFaceDetected();
  }, [wakeupMethod, onFaceDetected]);

  return {
    videoRef,
    canvasRef,
    isDetecting,
    cameraActive,
    cameraError,
    motionLevel,
    detectedType,
    lastDetectionTime,
    processedFramesCount,
    wakeupMethod,
    motionSensitivity,
    showDebugInfo,
    simulateDetection,
    startCamera,
    stopCamera,
  };
}
