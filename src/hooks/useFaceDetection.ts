import { useEffect, useRef, useState, useCallback } from "react";

interface FaceDetectionOptions {
  enabled: boolean;
  interval: number; // in seconds
  onFaceDetected: () => void;
}

export function useFaceDetection({ enabled, interval, onFaceDetected }: FaceDetectionOptions) {
  const [isDetecting, setIsDetecting] = useState<boolean>(false);
  const [cameraActive, setCameraActive] = useState<boolean>(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [motionLevel, setMotionLevel] = useState<number>(0);
  const [lastDetectionTime, setLastDetectionTime] = useState<Date | null>(null);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const intervalIdRef = useRef<number | null>(null);
  const prevImageDataRef = useRef<Uint8ClampedArray | null>(null);

  // Stop camera tracks cleanly
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

  // Frame processing step: checks for motion/presence
  const processFrame = useCallback(async () => {
    if (!videoRef.current || !canvasRef.current || videoRef.current.readyState < 2) return;

    const video = videoRef.current;
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d", { willReadFrequently: true });
    if (!ctx) return;

    const width = 64; // Low res for fast CPU-efficient analysis
    const height = 48;
    canvas.width = width;
    canvas.height = height;

    try {
      ctx.drawImage(video, 0, 0, width, height);

      // Check native FaceDetector if supported in Chromium
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const FaceDetectorAPI = (window as any).FaceDetector;
      if (FaceDetectorAPI) {
        try {
          const detector = new FaceDetectorAPI({ fastMode: true, maxDetectedFaces: 3 });
          const faces = await detector.detect(canvas);
          if (faces && faces.length > 0) {
            setLastDetectionTime(new Date());
            onFaceDetected();
            return;
          }
        } catch {
          // Fall back to pixel optical diff
        }
      }

      // Optical motion difference calculation
      const currentData = ctx.getImageData(0, 0, width, height).data;
      if (prevImageDataRef.current) {
        let diffCount = 0;
        const totalPixels = width * height;
        for (let i = 0; i < currentData.length; i += 4) {
          const rDiff = Math.abs(currentData[i] - prevImageDataRef.current[i]);
          const gDiff = Math.abs(currentData[i + 1] - prevImageDataRef.current[i + 1]);
          const bDiff = Math.abs(currentData[i + 2] - prevImageDataRef.current[i + 2]);
          if (rDiff + gDiff + bDiff > 45) {
            diffCount++;
          }
        }

        const deltaPercentage = (diffCount / totalPixels) * 100;
        setMotionLevel(Math.round(deltaPercentage));

        // Threshold of motion to indicate user arrival/movement
        if (deltaPercentage > 8.0) {
          setLastDetectionTime(new Date());
          onFaceDetected();
        }
      }

      prevImageDataRef.current = new Uint8ClampedArray(currentData);
    } catch {
      // Ignored cross-origin / draw failures
    }
  }, [onFaceDetected]);

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

      // Start detection loop based on configured interval (ms)
      const intervalMs = Math.max(100, interval * 1000);
      intervalIdRef.current = window.setInterval(processFrame, intervalMs);
    } catch (err: unknown) {
      console.warn("Camera could not be accessed for face detection:", err);
      setCameraError(err instanceof Error ? err.message : "Camera access denied or unavailable");
      setCameraActive(false);
      setIsDetecting(false);
    }
  }, [enabled, interval, processFrame]);

  // Restart camera when enabled or interval changes
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
    setLastDetectionTime(new Date());
    setMotionLevel(95);
    setTimeout(() => setMotionLevel(0), 1500);
    onFaceDetected();
  }, [onFaceDetected]);

  return {
    isDetecting,
    cameraActive,
    cameraError,
    motionLevel,
    lastDetectionTime,
    videoRef,
    canvasRef,
    startCamera,
    stopCamera,
    simulateDetection,
  };
}
