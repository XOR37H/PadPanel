# PadPanel - A Home automation kiosk for older iOS 15.x.x legacy devices.

PadPanel is a lightweight iOS app built for legacy devices such as the iPad Air2.
This is work progress, but PadPanel currently offers a veriaty of features that 
are well suited to home automation. 

<img src="https://github.com/XOR37H/PadPanel/blob/main/.github/assets/screenshots/screenshot_splash.jpg" alt="Splash" width="50%">

## Original Features

- Full‑screen kiosk-mode display of home automation dashboards.
- Slideshow mode cycle through multiple URLs with smooth cross-fade transitions at a configurable interval
- Screensaver after inactivity
- Wake the display via face detection using the device camera
- Wake-word detection via [Picovoice Porcupine](https://picovoice.ai/platform/porcupine/)
- Voice satellite for the Home Assistant Voice Pipeline
- MQTT allows GET / SET of various iPad telemetry options


## New features

- arm64 (iPad Air 2 / A8X compatible)
- Added choice of motion detection or face detection unlock plus sensitivity in settings.
- Added debug output for camera face/motion detection (enable/disable in settings)
- Added auto reload/refresh time and enable/disable to settings.
- Added WebUI for easy configuration
- Added ability to grab screenshots from dashboard.
- Added config backup & restore via webUI
- Added various screensaver options (Clock, Dim display, URL cycle)

## Releases

[Download the latest release](../../releases/latest)


## License
MIT License. See `LICENSE` for details.
