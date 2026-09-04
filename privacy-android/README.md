# PrivacyChain Android

PrivacyChain is a clean Android client prototype built around a Mihomo core boundary, residential SOCKS5 landing chains, and leak-resistant defaults.

## Product goal

The app is intentionally not another full Clash UI. Its first-class workflow is:

`airport node -> residential SOCKS5 -> Internet`

The client also treats DNS, IPv6, UDP/STUN, failure fallback, and local environment consistency as privacy surfaces that should be visible to the user.

## Current milestone

Implemented:

- Kotlin + Jetpack Compose standalone Android app under `privacy-android/`
- Four primary screens: Home, Nodes, Chain, Privacy
- Residential SOCKS5 profile model
- Android VPN permission boundary
- Mihomo runtime overlay builder for residential `dialer-proxy`
- Strict-route / DNS-hijack TUN policy generation
- Privacy check result model
- Environment target profile for timezone/language consistency
- Android auto-backup disabled and cleartext traffic disabled
- GitHub Actions debug APK build

Not implemented yet:

- Mihomo binary / lib integration
- TUN file descriptor handoff
- Subscription import and provider parsing
- Real DNS / IPv4 / IPv6 / UDP / STUN leak probes
- Encrypted credential persistence via Android Keystore
- Kill-switch enforcement after core failure
- System environment synchronization permission modes

## Security defaults

The design follows a fail-closed policy for privacy-sensitive paths: if a chained route cannot be confirmed, the intended behavior is to block instead of silently falling back to DIRECT.

Source subscriptions are treated as immutable inputs. Chain behavior is applied to generated runtime configuration instead of rewriting subscription files.

## Build

The CI workflow builds with JDK 17, Android API 37, Gradle 9.6.0, AGP 9.4.0, and the Compose 2026.08 BOM.
