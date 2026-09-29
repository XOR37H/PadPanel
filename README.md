# PadPanel iOS 15 build for legacy devices


PadPanel is a lightweight iOS app that displays any webpage in full‑screen kiosk mode. It can also act as a voice satellite. A common use case is a wall‑mounted iPad as a smart display.

## Features
- Full‑screen kiosk-mode display of Home Assistant dashboards (works best with HACS "Kioskmode")
- **Slideshow mode**: cycle through multiple dashboards with smooth cross-fade transitions at a configurable interval
- Screensaver after inactivity
- Wake the display via face detection using the device camera
- Wake-word detection via [Picovoice Porcupine](https://picovoice.ai/platform/porcupine/)
- Voice satellite for the Home Assistant Voice Pipeline
- iOS deployment target 15.0
- arm64 (iPad Air 2 / A8X compatible)

## New features
- Added choice of motion detection or face detection unlock plus sensitivity in settings.
- Added debug output for camera face/motion detection (enable/disable in settings)
- Added auto reload/refresh time and enable/disable to settings.

## License
MIT License. See `LICENSE` for details.