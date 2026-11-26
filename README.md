# e11: Remote Play

Play your PS5 or PS4 on your Mac, at home or away, with a controller.

- Metal and MetalFX upscaling, Neural Engine upscaling and Pro Motion frame generation
- Colour grades, including the "Game" look
- 1080p streaming by default
- Simple setup for linking a console and signing in to PSN
- Screenshots, mouse aim and Mac controller fixes

Get the app on the Mac App Store. This repository is the source code.

## Building

CMake + Ninja, Qt 6, FFmpeg, OpenSSL 3, SDL and libplacebo.

Mac App Store build:

```
TEAM_ID=ABCDE12345 PROFILE=path/to/profile.provisionprofile BUILD_NUMBER=1 \
  scripts/macos/build-appstore.sh
```

## License and credits

GNU Affero General Public License v3 with the OpenSSL exception; see [COPYING](COPYING) and
[LICENSES/](LICENSES). Includes code from Chiaki and chiaki-ng (see [README-chiaki-ng.md](README-chiaki-ng.md)).

Not endorsed or certified by Sony Interactive Entertainment. PlayStation, PS4, PS5 and DualSense
are trademarks of Sony Interactive Entertainment Inc.
