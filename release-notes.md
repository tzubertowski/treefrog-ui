## What's new

### Video and device fixes

- SF3000/SF3500 integer scaling uses a cached 640×480 canvas with black bars; the hot 2× path keeps the work on the fast pixel-copy path while HCGE handles panel presentation.

### UI and input

- **R36SX FN button:** the mapping wizard detects the physical FN key and adds
  it as the fifteenth bindable button; other devices retain the normal layout.
- **PicoArch in-game menu:** the physical FN button now opens the PicoArch menu directly on R36* devices.
- **Shutdown app:** Apps now includes a one-step poweroff action that syncs the card before turning off the console.
- Settings categories are collapsible and remember their state across reboots.
- Per-system extension whitelists hide non-launchable PS1 companion files while
  keeping the folder filter configurable.
- Folder results and filter data are cached so entering Games and Apps does not
  rescan the SD card unnecessarily.
- ROM names now use UTF-8 decoding with fallback fonts for Latin Extended
  (including Polish), Cyrillic, Greek, Japanese, Korean, and Chinese text in
  both FrogUI and picoarch menus.
- FrogUI and PicoArch now share editable runtime language packs. English,
  Polish, Spanish, Brazilian Portuguese, and Japanese are translated; Russian
  and Simplified Chinese are ready as community-editable starter packs.
- When a selected language needs glyphs outside the chosen UI font, FrogUI
  switches the complete UI to its heavier Unicode fallback face for a
  consistent result.
- Polish now uses the complete Latin Extended fallback across the whole UI, so
  accented letters such as `Ę`, `Ł`, and `Ź` render correctly and consistently.
- Friendly System Names now come from the same editable language packs. Official
  platform names remain canonical, while descriptive labels are localized.
- Finishing Button Mapping now returns cleanly to Settings instead of dropping
  into a stale system-grid view; malformed hand-edited keymaps are rejected
  safely.

### Experimental PSP support

- Added a `roms/psp/` entry and PSP theme artwork.
- PSP launch prefers an optional `cubegm/ppsspp` standalone binary and falls back to `ppsspp_libretro.so` when it is absent.
- The standalone source is tracked through <https://github.com/DevBobby-REP/PPSSPP-DATAFROGSF3000>.
- PPSSPP remains experimental and is not enabled as a guaranteed working emulator; see [the development investigation](docs/dev/ppsspp-investigation.md).

### Contributors

- **[@ozkaoz](https://github.com/ozkaoz)** — R36SX FN-button implementation and
  physical validation.
- **[MartStartIV](https://github.com/MartStartIV)** — Spanish translation.
- **[Maheshivara](https://github.com/Maheshivara)** — Brazilian Portuguese
  translation.
- **@Q_ta** — Japanese translation.

### Install or update

Recommended: use the [TreeFrogUI Installer](https://github.com/tzubertowski/TreeFrogUI-installer/releases/latest).

Manual fallback:

- Fresh install: apply `install_first/<device>/` from the full package.
- Update: copy `update.zip` to the SD-card root and reboot.

Keep the original SD-card backup before applying an update.
