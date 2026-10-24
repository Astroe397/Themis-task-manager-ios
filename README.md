# Themis for iPhone

SwiftUI / SwiftData port of Themis Mobile (Android). iOS 17+, iPhone only.

## What is ported
Dashboard (streak, 26-week heatmap, average-day donut, quote, dark theme), daily and one-off tasks, weight tracker with chart,
muscle strength ranks (9 tiers, logging, promotion, share card), GPS activity tracking (Kalman filter, Douglas-Peucker,
pedometer, MapKit route, background location), workout summary and share card, 10-Min Reset (breathing circle, looping audio,
CoreHaptics), water reminders, and LAN sync with the desktop app (same `/api/v1/sync/*` protocol, last-write-wins).

## Codemagic
1. Put the contents of this folder at the root of a Git repo and add it to Codemagic. `codemagic.yaml` is detected.
2. Run **themis-ios-test**: unsigned simulator build, artifact `Themis-simulator.app.zip`. No Apple account needed.
3. For a real iPhone use **themis-ios-device** after connecting an App Store Connect API key under Teams > Integrations.
   Change `com.themis.mobile` to your own bundle id if needed.

## Differences from Android
- Desktop discovery: iOS limits UDP broadcast (Local Network permission, possibly the multicast entitlement). If the desktop
  is not found, type its IP on the Dashboard under "Desktop address".
- Water reminders are pre-scheduled local notifications (next 60 half-hours, refilled whenever the app opens) with fixed messages
  instead of a live quote.
- Maps use Apple MapKit instead of MapLibre. Instagram-Story deep link is replaced by the standard iOS share sheet.
- The original logo/launcher PNGs were not in the export, so a generated placeholder icon is used. Replace
  `Themis/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
- Built in Swift 5 language mode for build reliability; this project was written without access to a Swift compiler, so the first
  Codemagic run may surface small compile errors to fix.
