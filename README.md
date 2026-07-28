# Presence

Presence is a private, native macOS menu-bar utility that keeps the display awake only while someone is at the Mac.

- Camera checks begin only after the configured keyboard and mouse inactivity.
- Face and upper-body detection run locally with Apple Vision.
- Frames are never stored or uploaded.
- A configurable grace period tolerates looking away and temporary occlusion.

## Build

Requires macOS 13 or newer and Xcode command-line tools.

```sh
make test
make app
```

The standalone app and clean distributable ZIP are created in `dist`. Move Presence to Applications before enabling **Launch at login**.
