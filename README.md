# Tripper Dash for iOS

An independent iOS companion app for the Royal Enfield Tripper Dash / Console.

## Current status

The Swift protocol core and a minimal SwiftUI diagnostic app are implemented on branch `ios/dash-auth-network`. The app can request connection to the known dashboard Wi-Fi network, open the UDP transport, and attempt the RSA/AES authentication handshake.

**Validation status:** package tests and the iOS Simulator build run in GitHub Actions. Physical connection to a Guerrilla 450 Tripper Dash has not yet been verified. A successful `NEHotspotConfigurationManager.apply` completion means the Wi-Fi configuration was applied; it does not, by itself, prove the phone has joined the network or that dashboard packets are flowing.

## Repository layout

- `Sources/TripperDashCore/K1GPacket.swift` — K1G packet construction, incoming TLV parsing, sequence patching.
- `Sources/TripperDashCore/DashCommands.swift` — startup/authentication request packets.
- `Sources/TripperDashCore/DashAuth.swift` — RSA-1024 / AES-256 authentication state machine.
- `Sources/TripperDashCore/DashUDPTransport.swift` — UDP control, receive and RTP sockets.
- `Sources/TripperDashCore/DashWiFiConnector.swift` — user-authorized Wi-Fi configuration through NetworkExtension.
- `Sources/TripperDashCore/DashSession.swift` — handshake coordinator, retries and receive watchdog.
- `App/` — SwiftUI diagnostic app and iOS privacy/entitlement configuration.

The Android `1857rebels/WayFindr` project is used only as a protocol reference; it is not modified by this project.

## Build and test

Requirements: Xcode with an iOS 16+ SDK and XcodeGen.

```sh
swift test
brew install xcodegen
xcodegen generate
xcodebuild -project TripperDash.xcodeproj \
  -scheme TripperDash \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Open `TripperDash.xcodeproj` in Xcode to run on a connected iPhone. Device installation requires a valid Apple development signing team and provisioning profile.

## First physical-device test

1. Power on the motorcycle and wait for the Tripper Dash Wi-Fi network to appear.
2. On the iPhone, keep the app in the foreground and tap **Connect to Tripper Dash**.
3. Approve the iOS Wi-Fi configuration prompt if shown.
4. Watch the Wi-Fi status, session status and received-packet counter.
5. If authentication fails, capture the full screen and note whether the iPhone shows `RE_TGNO_260915` as its connected Wi-Fi network in Settings.

Do not treat the Wi-Fi configuration callback alone as proof of a successful connection. The meaningful milestone is receiving the dashboard's key offer and reaching the authenticated session state.

## iOS permissions

- `NSLocalNetworkUsageDescription` is present for local-network access.
- The app includes the Hotspot Configuration entitlement needed to use `NEHotspotConfigurationManager`. Apple documents this entitlement as the permission for apps to configure Wi-Fi networks: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration
- The entitlement must also be enabled for the app identifier in the Apple Developer account before a signed device build can use it.

## Scope

This is currently a diagnostic connection/authentication app. It does not yet send navigation instructions or video. Protocol compatibility and any future streaming features must be validated against physical hardware before being described as supported.
