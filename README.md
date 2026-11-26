# Five Skies

Five Skies (working title) is an iPhone app for Muslims: prayer times, adhan, Quran and Qibla.
Its Today screen shows a full-screen living sky that changes with the current prayer period:
pre-dawn for Fajr, bright noon for Dhuhr, golden afternoon for Asr, sunset for Maghrib and night for Isha.

The app is free and has no ads. It has no analytics and sends nothing off the device.

## How the build works

- The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  No `.xcodeproj` is checked in.
- Prayer times come from the [Adhan](https://github.com/batoulapps/adhan-swift) Swift package.
- GitHub Actions (`.github/workflows/ios.yml`) runs on every push to `main` and on demand. It generates the
  project, builds the app, runs the unit and UI tests on an iPhone simulator, and uploads the Today screen
  screenshots (one per sky) and the full test results as build artifacts.

To build locally on a Mac with Xcode 16 or later:

```sh
brew install xcodegen
xcodegen generate
open FiveSkies.xcodeproj
```

For deterministic screenshots, launch with `-FSFixedPhase <fajr|dhuhr|asr|maghrib|isha>`. The app then uses
Makkah as its location, skips the location prompt, and freezes time in the middle of that sky.

## Status

This first milestone includes:

- A five-tab layout: Today, Quran, Listen, Qibla, More. Only Today is built; the other tabs say "Coming soon".
- Prayer times for the day from the Adhan library (default method: North America (ISNA), Shafi madhab).
- The living sky: five gradients, stars, sun or moon, and a mosque skyline, crossfading between periods.
- Next prayer with a live countdown.
- Five prayer tiles that can be marked as prayed, saved per day on the device.
- Device location with permission, or Makkah as a clearly labelled fallback.
- Unit tests, UI tests with screenshots, and CI on GitHub Actions.

## License

License: to be decided.
