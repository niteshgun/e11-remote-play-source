# e11: Remote Play

*Made by e11hours AI Studio, vibe-coded by Claude.*

Play your PS5 or PS4 on your Mac, at home or away, with a controller.

## Play GTA VI on your Mac

GTA VI is out on PS5, and there's no Mac version. With e11: Remote Play you can play your own
copy on your Mac: stream it from your PS5 at home or away, with a PS5 controller or mouse and
keyboard (GTA-style keys and mouse aim built in).

- **Pro Motion frame generation:** 60 fps from the PS5 becomes up to 120 fps on ProMotion displays
- **MetalFX upscaling:** a sharper picture at your Mac's full screen resolution
- **Lag guard:** quality steps back the moment it could add lag

You need a PS5, your copy of the game, and a good network connection.

## Features

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

Not endorsed or certified by Sony Interactive Entertainment, Rockstar Games or Take-Two Interactive.
PlayStation, PS4, PS5 and DualSense are trademarks of Sony Interactive Entertainment Inc.
Grand Theft Auto and GTA are trademarks of Take-Two Interactive Software, Inc.
e11: Remote Play does not include any games.
