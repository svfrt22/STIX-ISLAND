# STIX Island

Dynamic Island for MacBooks with a notch: music, charging, volume & brightness,
headphones, timer and AirDrop drop zone — in a single minimal black island.

## Install
1. Open **Releases** and download the latest `STIX-Island-x.y.z.zip`.
2. Unzip and move **STIX Island.app** to **Applications**.
3. First launch: open Terminal and run
   `xattr -cr "/Applications/STIX Island.app"`, then open the app.
4. Grant **Accessibility** (System Settings → Privacy & Security → Accessibility)
   so volume/brightness show in the island.

## Build
Every push to `main` is built by GitHub Actions on macOS and published to Releases.
Local build (needs Xcode Command Line Tools): `./scripts/build-app.sh`.

## License
GPL-3.0. See LICENSE and NOTICE.
