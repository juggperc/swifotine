# Swifotine Licensing Notes

Swifotine combines a Native macOS app frontend (Swift/SwiftUI) and a Python backend (nicotine-plus) via an out-of-process helper model.

## Nicotine+ Upstream

- **License:** Nicotine+ is licensed under the GNU General Public License v3 or later (GPL-3.0-or-later).
- **Submodule / Redistribution:** Nicotine+ source is integrated as a git submodule (`vendor/nicotine-plus`).
- **GPL-Compatible Distribution:** Any application incorporating nicotine+ via embedded codebase or integrated packaging often adopts GPLv3. Swifotine will comply with GPL-3.0 licensing requirements. End-user binaries distributed to any internal/external audience will include GPL notices and full source availability.

## Important Dependencies

- `nicotine-plus` dependencies (e.g. mutagen, geoip) are inherited and bound by their respective open source licenses.

## Compliance

- Swifotine avoids private APIs to maintain App Store/Mac App Store compliance, although initial distribution is developer/test.
- Licensing notices and bundled third-party licenses are kept visible in-app.
- Notarization and signing pipelines will be established.
