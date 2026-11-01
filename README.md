# tripper-dash-ios

Independent iOS companion app for the Royal Enfield Console / Tripper Dash.

## Current status

The first protocol-core milestone is implemented in Swift on branch `ios/dash-auth-network`. The Android WayFindr project is used only as a protocol reference; this repository contains an independent Swift implementation.

### Core modules

- `K1GPacket`: K1G packet construction, incoming TLV parsing and rolling sequence patching.
- `DashAuth`: RSA-1024 / AES-256 authentication state machine.
- `DashUDPTransport`: UDP control broadcast, receive socket and RTP sender.

## Build

Open the package in Xcode or run:

```sh
swift test
```

## Important iOS integration notes

- Wi-Fi association is a user-authorized operation. The app will use NetworkExtension's `NEHotspotConfigurationManager` in the app layer; it cannot silently join arbitrary networks.
- Add the Hotspot Configuration capability/entitlement in the Xcode target before using that API.
- iOS local-network privacy requires an appropriate `NSLocalNetworkUsageDescription` in the app's Info.plist.
- The UDP transport assumes the phone is already connected to the dashboard Wi-Fi. Device testing is required to confirm route selection, broadcast delivery and the dashboard's response.
- The exact SSID is included in the RSA-encrypted authentication payload. Prefix discovery must resolve and retain the actual SSID before authentication.

## Scope

This repository is intended for personal, non-commercial motorcycle dashboard integration and open-source development. Protocol compatibility must be validated against physical hardware before being described as supported.
