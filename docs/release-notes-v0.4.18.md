# Amanu 0.4.18

## Analytics delivery

- Fixed analytics events being rejected because their timestamps included fractional seconds. Existing queued events are converted automatically.
- Events are now removed from the local queue only after validating the server's acknowledgement. Failed entries remain queued, and successful entries in a partially accepted batch are not resent.
- Large backlogs are split into requests within the server's limit. The existing opt-out, seven-day retention and 500-event queue limit remain in effect.
- Events already discarded by earlier versions cannot be recovered. Statistics begin accumulating as updated installations send events.

## Automatic recording

- Expanded default call detection to WhatsApp, Signal, Telegram Desktop, Viber, LINE, WeChat and current Webex.
- Added Opera, Vivaldi, Chromium, Yandex Browser, DuckDuckGo, Orion, Zen and Dia for calls in browser tabs. Existing custom application lists remain unchanged.

## Compatibility

- Release packaging now discovers SwiftPM's output directory, including the new Xcode 27 build engine.
- Universal binary for Apple Silicon and Intel Macs running macOS 15 or later. Intel requires a cloud transcription key and has not been tested on physical hardware.
- Audio capture and echo-suppression behavior are unchanged in this release.
