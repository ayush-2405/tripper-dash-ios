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

### Install on your iPhone

1. On a Mac, install Xcode and XcodeGen (`brew install xcodegen`).
2. Clone this repository and check out `ios/dash-auth-network`.
3. From the repository root, run `xcodegen generate`.
4. Open `TripperDash.xcodeproj` in Xcode.
5. Connect your iPhone by cable, unlock it, and trust the Mac if prompted.
6. Select the `TripperDash` target → **Signing & Capabilities** → enable **Automatically manage signing** → select your Apple Development team.
7. Confirm the bundle identifier is unique to your account if Xcode asks you to change it.
8. Select your iPhone as the run destination and press **Run**. Accept the developer-mode/trust prompts on the phone if iOS displays them.

A free Personal Team may be sufficient for a local development install, but Apple's Hotspot Configuration entitlement must be available to the selected signing team and included in its provisioning profile. If Xcode reports that the entitlement is not permitted, the app cannot use the in-app Wi-Fi join flow with that profile; do not remove the entitlement and assume the flow will work. We can adapt the test to manual Wi-Fi association if needed.

CI now builds both the Simulator target and the generic physical-device target without signing. This verifies compilation for device architecture, but it does not create an installable IPA or replace Xcode signing.

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
