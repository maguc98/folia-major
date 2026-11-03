# Folia iOS IPA (eSign)

This is an experimental Capacitor wrapper for the Folia web application. It does not convert Electron desktop features into iOS-native features.

## Build

The GitHub Actions workflow `.github/workflows/ios-esign-ipa.yml` runs on GitHub-hosted macOS and creates an **unsigned IPA**. It does not need an Apple signing certificate or provisioning profile in GitHub Secrets.

Run it from the Actions tab using **Build Folia iOS IPA (eSign) → Run workflow**. Download the `Folia-iOS-unsigned-<run number>` artifact after the job succeeds.

## Sign and install with eSign

1. Export your own Apple signing certificate and private key as a `.p12` file, and obtain the matching provisioning profile (`.mobileprovision`).
2. Import both into eSign on your iPhone.
3. Import `Folia-iOS-unsigned.ipa` into eSign.
4. Select the matching certificate and provisioning profile, then sign the IPA.
5. Install the signed app from eSign.

The provisioning profile must permit the app's bundle identifier, currently `top.izuna.foliamajor`. A profile with a different App ID will require changing the Capacitor `appId` and rebuilding.

**Never upload your .p12 file, certificate password, or provisioning profile to this repository or to workflow artifacts.** The workflow intentionally produces an unsigned app so signing remains on your device.

## Current scope and limitations

- The iOS target is a Capacitor/WKWebView wrapper around the built web application.
- Electron-only desktop functions are not available in this iOS wrapper.
- iOS background audio, lock-screen controls, local media-library access, and native file access are not claimed as supported by this initial build.
- Online music and AI features may require the same backend URLs and service configuration as the Web deployment. A successful IPA build alone does not guarantee those services are configured.
- The first build is a packaging baseline. Install and test it on a real iPhone before treating it as a daily-use release.
