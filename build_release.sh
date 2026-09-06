#!/bin/bash
# Build the unified TreeFrogUI release: release/latest/release/
#
# ONE package for R36SX / SF3000 / SF3500. Boot is unified on the rkgame autorun
# hijack - the stock boot chain (icube + rkgame, both verified on SF3500) is
# NEVER touched on any device:
#
#   stock boot -> rkgame -> setting.xml <autorun> -> libemu_tfhijack.so
#     -> retro_load_game() execl's zhijack.sh -> picoarch/frogui
#
# Layout:
#   release/latest/release/cubegm,frogui,roms,MD  universal payload - copy to SD
#   release/latest/release/install_first/<dev>/ per-device setup
#                                core override, boot logo, and the device's
#                                GENERATED zhijack.sh (hardcoded device facts,
#                                no runtime detection) - user copies THEIR device's
#   release/latest/release/INSTALL.md           guide
set -e
cd "$(dirname "$0")"

STAGE=sdcard
HIJACK=hijack
RELEASE_ROOT=release
OUT="$RELEASE_ROOT/latest/release"
# WORKING autoboot recipe (confirmed on SF3500 hardware, see project_sf3500_hijack):
#   - autorun rom path must be ABSOLUTE (relative is silently ignored by rkgame)
#   - driver="" → rkgame resolves the core by the rom's EXTENSION via config.xml
#   - so we OVERRIDE the stock core for that extension with our hijack core.
# .md → libemu_md.so (picodrive) on every stock config.xml → override that one.
HIJACK_CORE="$HIJACK/libemu_tfhijack.so"  # built libretro stub that execl's zhijack
OVERRIDE_CORE="libemu_md.so"              # stock MD core we replace (.md extension)
DUMMY_REL="MD/dummy.md"                   # dummy rom (extension picks the core)
DUMMY_ABS="/mnt/sdcard/$DUMMY_REL"        # rkgame needs the ABSOLUTE path

PICOARCH=/home/tomaszz/sf3000-work/picoarch/picoarch
PICOARCH_HI=/home/tomaszz/sf3000-work/picoarch/picoarch_hi
FROGUI=/home/tomaszz/sf3000-work/FrogUI/frogui_libretro.so
FROGSHELL=/home/tomaszz/sf3000-work/FrogShell
FROGSHELL_ASSET="$(pwd)/assets/frogshell_libretro.so"
TYRQUAKE=/home/tomaszz/sf3000-work/tyrquake-og/tyrquake_libretro.so
# CI/release builders can provide the small per-device stock bootstrap files
# from a previous full release instead of keeping proprietary stock SD images
# in the workspace. Each directory must contain setting.xml.
STOCK_FALLBACK=${TREEFROG_STOCK_ROOT:-}

# device name -> stock cubegm path (for generating per-device xml)
declare -A STOCK=(
  [r36sx]=/home/tomaszz/sf3000-work/R36SX_sdcard/cubegm
  # R36 HD (R36S-H) = clone-of-a-clone. Ran the R36SX build fine on 1.0.1 with the
  # pristine driver_r36sx.so; 1.0.2's driver27 self-select swapped it to the
  # 2.7-stubbed driver_r36sx27.so and killed its panel. This variant is R36SX with
  # the @R36@ self-select STRIPPED (non-r36sx dev → else-branch), so it stays on
  # the proven driver_r36sx.so and never swaps. Reuses the R36SX stock xml/boot.
  [r36hd]=/home/tomaszz/sf3000-work/R36SX_sdcard/cubegm
  [sf3000]=/home/tomaszz/sf3000-work/SF3000_sdcard/SF3000_sdcard/cubegm
  [sf3500]=/home/tomaszz/sf3000-work/SF3500_sdcard_v1.1/cubegm
  # SF3000_HD = HDMI-out variant. Same SoC/panel(854x480)/disp_frame as SF3500,
  # byte-identical encrypted driver.so, identical config/filelist. It even detects
  # AS SF3500 at runtime (has /panel) and loads driver_sf3500.so - correct. This
  # folder just gives HD owners a labelled, ready-to-copy xml set.
  [sf3000hd]=/home/tomaszz/sf3000-work/SF3000_HD_sdcard_v1.1/cubegm
  # SF3100 = yet another SF3500-clone. Encrypted driver.so is BYTE-IDENTICAL to
  # SF3500/HD (same md5), config/filelist identical, 854x480 panel. Detects AS
  # SF3500 (has /panel, no multiple_init) and loads driver_sf3500.so - correct.
  [sf3100]=/home/tomaszz/sf3000-work/SF3100_sdcard/cubegm
  # GB350 = 640x480 4:3 device. /panel present but, alone among /panel devices,
  # lacks both multiple_init and uart@1 → detected as its own device. Plain-ELF
  # driver (NOT encrypted, unique) shipped as driver_gb350.so. config/filelist
  # identical to R36SX. Rides the SF3000 disp_frame path at 640x480.
  [gb350]=/home/tomaszz/sf3000-work/GB350_sdcard/cubegm
)

# Per-device zhijack.sh facts (generated from hijack/zhijack.tpl.sh - NO runtime
# device detection on the SD). Geometry from the stock dtbs. RKGAME policy:
#   kill = killall before frogui/game (proven on SF-class disp_frame devices)
#   stop = SIGSTOP once at boot (R36SX: killing → icube respawns rkgame which
#          redraws over fb-write = flicker; leaving it RUNNING → it reacts to
#          SELECT+START (stock exit-game hotkey) and draws over the screen)
#            TF_DEVICE W   H   ASPECT ROT PRESENT   DRIVER            RKGAME
declare -A HJ=(
  [r36sx]="   R36SX    640 480 4  3   0   fbwrite   driver_r36sx.so   stop"
  [r36hd]="   R36SX    640 480 4  3   0   fbwrite   driver_r36sx.so   stop"
  # SF3000's portrait framebuffer is presented clockwise by disp_frame. The
  # standalone media decoders consume this value, so keep it at 90 degrees.
  # FrogShell is now a libretro core and is rotated by picoarch's SF display
  # path; the old 270-degree standalone-shell value double-rotates media.
  [sf3000]="  SF3000   854 480 16 9   90  dispframe driver_sf3000.so  kill"
  [sf3500]="  SF3500   854 480 16 9   90  dispframe driver_sf3500.so  kill"
  [sf3000hd]="SF3500   854 480 16 9   90  dispframe driver_sf3500.so  kill"
  [sf3100]="  SF3500   854 480 16 9   90  dispframe driver_sf3500.so  kill"
  [gb350]="   GB350    640 480 4  3   0   dispframe driver_gb350.so   kill"
)

# Per-device cubevol sleep-arm text addresses for the nosleep live-patcher.
# Each address includes the expected original MIPS instruction; nosleep refuses
# to patch when it does not match. This is essential because compatible devices
# ship several different cubevol ELFs at the same /usr/bin/cubevol path.
# (opt-in via FrogUI Settings -> "Disable Sleep"). NOPed in RAM so the on-disk
# cubevol stays pristine (SF3500 boot-verifies it). Empty = not supported/tested
# on that device (sleep lives elsewhere, or cubevol differs). Addresses are the
# stores that ARM sleep: tap, idle-timeout, set_sleep_mode_state, msg-269 send.
declare -A NOSLEEP_ADDRS=(
  # Original R36SX plus the newer R36SX v2.7/R36HD cubevol variant. Only the
  # three instructions matching the running ELF are touched.
  [r36sx]="0x406d24:0xac62bb18 0x40701c:0xae02bb18 0x406b50:0xac44bb18 0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
  [r36hd]="0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
  [sf3500]="0x406d44:0xac62bb78 0x40703c:0xae02bb78 0x406b70:0xac44bb78 0x406d8c:0x0c10162b"
  [sf3000hd]="0x406d44:0xac62bb78 0x40703c:0xae02bb78 0x406b70:0xac44bb78 0x406d8c:0x0c10162b"
  [sf3100]="0x406d84:0xac62bcc8 0x407088:0xae02bcc8 0x406bb0:0xac44bcc8"
  [gb350]="0x406bd4:0xac62b758 0x406ecc:0xae02b758 0x406a00:0xac44b758"
)

# 0) Refresh staging + build hijack core.
# Guard: picoarch_hi (gpsp/pcsx dynarec build of the SAME source) must not be older
# than picoarch - a stale hi carries old device detection → SF3500/HD mis-detect →
# wrong driver → gpsp/pcsx audio crash. build_sf3000.sh builds ONLY picoarch.
if [ "$PICOARCH" -nt "$PICOARCH_HI" ]; then
    echo "WARN: picoarch is newer than picoarch_hi - rebuild it: (cd ../picoarch && sh build_picoarch_hi.sh)"
fi
make -C apps/video_player >/dev/null
make -C apps/image_viewer >/dev/null
if [ -d "$FROGSHELL" ]; then
    make -C "$FROGSHELL" TARGET="$(pwd)/sdcard/cubegm/cores/frogshell_libretro.so" >/dev/null
fi
cp_if_diff() { [ -f "$1" ] || return 0; cmp -s "$1" "$2" && return 0; cp "$1" "$2"; }
cp_if_diff "$PICOARCH"    "$STAGE/cubegm/picoarch"
cp_if_diff "$PICOARCH_HI" "$STAGE/cubegm/picoarch_hi"
cp_if_diff "$FROGUI"      "$STAGE/cubegm/cores/frogui_libretro.so"
# Runtime language packs are FrogUI data, not compiled-in strings. Keep the
# staged copy in sync so release archives and local deployments behave alike.
mkdir -p "$STAGE/frogui/lang"
rsync -rlt "$(dirname "$FROGUI")/lang/" "$STAGE/frogui/lang/"
# Polish and other Latin-Extended packs need DejaVu rather than the bundled
# CJK face. Source it from FrogUI so CI releases do not depend on a stale SD
# staging tree.
mkdir -p "$STAGE/frogui/fonts"
cp_if_diff "$(dirname "$FROGUI")/fonts/TreeFrogLatin.ttf" "$STAGE/frogui/fonts/TreeFrogLatin.ttf"
cp_if_diff "$TYRQUAKE"    "$STAGE/cubegm/cores/tyrquake_libretro.so"
# CI does not have the FrogShell checkout. Keep the tested libretro core
# in-tree so release builds use the same picoarch display path as local builds.
cp_if_diff "$FROGSHELL_ASSET" "$STAGE/cubegm/cores/frogshell_libretro.so"
sh "$HIJACK/build_tfhijack.sh" >/dev/null
cp_if_diff "$HIJACK/nosleep" "$STAGE/cubegm/nosleep"

mkdir -p "$RELEASE_ROOT/artifact" "$RELEASE_ROOT/latest"
rm -rf "$OUT"
mkdir -p "$OUT/cubegm/cores" "$OUT/cubegm/lib" "$OUT/$(dirname "$DUMMY_REL")"

# 1) Universal payload - our files only, NO stock, NO icube.
cp -a "$STAGE/cubegm/cores/." "$OUT/cubegm/cores/"
for f in picoarch picoarch_hi nosleep driver_r36sx.so driver_r36sx27.so driver_sf3000.so driver_sf3500.so driver_gb350.so; do
    cp "$STAGE/cubegm/$f" "$OUT/cubegm/$f"
done
cp "$HIJACK/tfupdate.sh" "$OUT/cubegm/tfupdate.sh"
chmod +x "$OUT/cubegm/tfupdate.sh"
# zhijack.sh is per-device (generated into install_first/<dev>/cubegm/ below) - # the universal payload deliberately ships NO launcher and NO device detection.
# only libs no stock device ships (SDL, png12). SD is FAT32 → NO symlinks: ship a
# REAL libSDL-1.2.so.0 (the soname the binaries link), cp -L dereferences the
# staging symlink. The .0.11.4 target name is not needed by anything.
cp -L "$STAGE/cubegm/lib/libSDL-1.2.so.0" "$OUT/cubegm/lib/libSDL-1.2.so.0"
cp    "$STAGE/cubegm/lib/libpng12.so.0"   "$OUT/cubegm/lib/libpng12.so.0"
# ppsspp_libretro.so links libpng16 (not the png12 the rest of the world uses);
# its assets ride along automatically via the cubegm/bios/PPSSPP staging copy.
cp    "$STAGE/cubegm/lib/libpng16.so.16"  "$OUT/cubegm/lib/libpng16.so.16"
[ -d "$STAGE/frogui" ] && cp -a "$STAGE/frogui" "$OUT/frogui"
# System View uses a small shared logo pack. Keep it outside ignored staging so
# the exact release assets are versioned and reproducible.
if [ -d "assets/system-icons" ]; then
    mkdir -p "$OUT/frogui/system-icons"
    cp -a assets/system-icons/. "$OUT/frogui/system-icons/"
fi
if [ -d "assets/icon-packs" ]; then
    mkdir -p "$OUT/frogui/icon-packs"
    cp -a assets/icon-packs/. "$OUT/frogui/icon-packs/"
fi
# roms/ folder structure (the system subfolders FrogUI expects: gba, nes, snes…).
# Ships empty folders + their .res/filelist scaffolding; users drop ROMs in.
[ -d "$STAGE/roms" ] && cp -a "$STAGE/roms" "$OUT/roms"
mkdir -p "$OUT/roms/images"
mkdir -p "$OUT/roms/music"

# Canvas ships hundreds of ES-DE targets and a second high-resolution mirror.
# FrogUI requests only exact ROM-folder names plus its four built-in screens.
# Keep the source pack intact for future mappings, but do not ship unreachable
# artwork on these small FAT32 cards.
CANVAS_OUT="$OUT/frogui/theme-packs/Canvas_Pastel"
if [ -d "$CANVAS_OUT" ]; then
    rm -rf "$CANVAS_OUT/Canvas_Pastel-hi"
    while IFS= read -r image; do
        name="$(basename "$image" .jpg)"
        case "$name" in
            main|recents|favourites|settings) continue ;;
        esac
        [ -d "$OUT/roms/$name" ] || rm -f -- "$image"
    done < <(find "$CANVAS_OUT" -maxdepth 1 -type f -name '*.jpg' -print)
fi

# 1b) Our extra assets the old release shipped (these are OURS, not stock OS):
#     standalone frontends, BIOS, boot logos. NOT shipped: icube/icube_start
#     (retired boot), cubevol + generic driver.so (stock), *.bak / test bins (junk).
# (boot logos are NOT shipped here - install_first/<dev>/ provides the device-correct
#  xgame-logo.bmp, so no fix_bootlogo script is needed.)
for x in lgpt lgpt.elf pcsx4all pico286 rockbox rockbox.sh ebook video_player image_viewer ppsspp; do
    [ -e "$STAGE/cubegm/$x" ] && cp -a "$STAGE/cubegm/$x" "$OUT/cubegm/$x"
done
install -m 0755 apps/usb_mode/usb_mode.sh "$OUT/cubegm/usb_mode.sh"
install -m 0755 apps/shutdown.sh "$OUT/cubegm/shutdown.sh"
install -m 0755 apps/usb_mode/usb_mtp.sh "$OUT/cubegm/usb_mtp.sh"
install -m 0755 apps/usb_mode/mtp-server "$OUT/cubegm/mtp-server"
install -m 0755 apps/usb_mode/usb_exit_watcher "$OUT/cubegm/usb_exit_watcher"
mkdir -p "$OUT/cubegm/modules/4.4.186-release"
install -m 0644 apps/usb_mode/modules/4.4.186-release/usb_f_mass_storage.ko \
    "$OUT/cubegm/modules/4.4.186-release/usb_f_mass_storage.ko"
install -m 0644 apps/usb_mode/modules/4.4.186-release/usb_f_mtp.ko \
    "$OUT/cubegm/modules/4.4.186-release/usb_f_mtp.ko"
[ -f rootfs-overlay/etc/mdev/mount-helper.sh ] && \
    { mkdir -p "$OUT/rootfs/etc/mdev" && \
      install -m 0755 rootfs-overlay/etc/mdev/mount-helper.sh \
          "$OUT/rootfs/etc/mdev/mount-helper.sh"; }
[ -d "$STAGE/cubegm/bios" ] && cp -a "$STAGE/cubegm/bios" "$OUT/cubegm/bios"

# 1c) Top-level docs + user-facing files the old release had (authoritative
#     install steps live in the generated INSTALL.md below; old install.md is
#     dropped as it documents the retired icube method).
# User-facing docs come from the REPO ROOT (canonical, maintained) - the sdcard/
# copies are stale stubs. Assets (picoarch.cfg) come from staging.
for x in README.md install.md theme.md LICENSE.md; do
    [ -f "$x" ] && cp "$x" "$OUT/$x"
done
mkdir -p "$OUT/docs"
for x in cores.md release-notes.md onionos_gap.md ARCADE_CORES.md; do
    [ -f "$x" ] && cp "$x" "$OUT/docs/$x"
done
[ -f "docs/RELEASING.md" ] && cp "docs/RELEASING.md" "$OUT/docs/RELEASING.md"
# README setup links point into docs/cores/. Ship the maintained guides with
# the release instead of leaving those links valid only in the source tree.
if [ -d "docs/cores" ]; then
    mkdir -p "$OUT/docs/cores"
    cp -a docs/cores/. "$OUT/docs/cores/"
fi
for x in picoarch.cfg; do
    [ -e "$STAGE/$x" ] && cp -a "$STAGE/$x" "$OUT/$x"
done

# Dummy autorun rom at the absolute path rkgame loads, + its folder catalog entry
# (filename,Display Name,SHORTCODE). The .md extension makes rkgame pick libemu_md.so
# - which install_first overrides with our hijack core.
printf 'TF' > "$OUT/$DUMMY_REL"
printf 'dummy.md,TreeFrogUI,MD\n' > "$OUT/$(dirname "$DUMMY_REL")/filelist.csv"

# 2) Per-device install_first - the WORKING hijack recipe:
#   a) setting.xml autorun -> ABSOLUTE dummy path, driver="" (extension-resolved)
#   b) cores/libemu_md.so OVERRIDDEN with our hijack core (so .md -> our core)
# We do NOT touch config.xml/filelist.xml - stock already maps .md -> libemu_md.so,
# and the override + driver="" is what actually boots (explicit driver=, relative
# paths, and a new core name all silently failed on hardware).
for dev in "${!STOCK[@]}"; do
    src="${STOCK[$dev]}"; dst="$OUT/install_first/$dev"
    if [ ! -f "$src/setting.xml" ] && [ -n "$STOCK_FALLBACK" ] &&
       [ -f "$STOCK_FALLBACK/$dev/cubegm/setting.xml" ]; then
        src="$STOCK_FALLBACK/$dev/cubegm"
    fi
    [ -d "$src" ] || { echo "WARN: no stock for $dev ($src) - skipping"; continue; }
    mkdir -p "$dst/cubegm/cores"
    cp "$src/setting.xml" "$dst/cubegm/setting.xml"
    ST="$dst/cubegm/setting.xml"
    sed -i "s#<autorun file=\"[^\"]*\" driver=\"[^\"]*\" />#<autorun file=\"$DUMMY_ABS\" driver=\"\" />#" "$ST"
    grep -q "file=\"$DUMMY_ABS\" driver=\"\"" "$ST" || echo "  WARN[$dev]: autorun not patched"
    cp "$HIJACK_CORE" "$dst/cubegm/cores/$OVERRIDE_CORE"
    #   c) device-correct boot logo (cubegm/xgame-logo.bmp). 640x480 panels (R36SX,
    #      GB350) use the original; 854x480 panels (SF3000/HD/SF3100/SF3500) use the
    #      SF3000-format one. Shipping it here replaces the old fix_bootlogo script.
    case "$dev" in
        r36sx|r36hd|gb350) logo="$STAGE/cubegm/xgame-logo.bmp" ;;
        *)           logo="$STAGE/cubegm/xgame-logo-sf3000.bmp" ;;
    esac
    [ -f "$logo" ] && cp "$logo" "$dst/cubegm/xgame-logo.bmp"
    #   d) the device's zhijack.sh, generated from the template with everything
    #      hardcoded (device, panel, driver, rkgame-kill policy). No DT probing.
    read -r DEV PW PH ASPN ASPD ROT PRESENT DRIVER KILL <<< "${HJ[$dev]}"
    [ -n "$DEV" ] || { echo "  WARN[$dev]: no HJ entry - no zhijack generated"; continue; }
    sed -e "s/@DEV_LABEL@/$dev/g" -e "s/@DEV@/$DEV/g" -e "s/@PW@/$PW/g" \
        -e "s/@PH@/$PH/g" -e "s/@ASPN@/$ASPN/g" -e "s/@ASPD@/$ASPD/g" \
        -e "s/@ROT@/$ROT/g" -e "s/@PRESENT@/$PRESENT/g" -e "s/@DRIVER@/$DRIVER/g" \
        -e "s#@NOSLEEP@#${NOSLEEP_ADDRS[$dev]:-}#g" \
        "$HIJACK/zhijack.tpl.sh" > "$dst/cubegm/zhijack.sh"
    # Boot block (freeze icube + kill rkgame) is universal. Loop killalls stay
    # only on kill-policy devices (harmless no-op belt on SF-class); r36sx runs
    # the tested no-loop-kill config.
    if [ "$KILL" = stop ]; then
        sed -i '/#@KILL@/d' "$dst/cubegm/zhijack.sh"
    else
        sed -i 's/ #@KILL@//' "$dst/cubegm/zhijack.sh"
    fi
    # R36SX-only block (@R36@: driver self-selection). Non-R36SX-only block
    # (@HW@: HW-render watchdog → force SW). R36SX renders via fb-write and has
    # no SW-transpose fallback tuned for its panel, so it never force-SWs.
    # R36HD is an R36SX-compatible clone and needs the same driver fallback
    # block; its panel and boot path are the proven R36SX configuration.
    if [ "$dev" = r36sx ] || [ "$dev" = r36hd ]; then
        sed -i -e 's/ #@R36@//' -e '/#@HW@/d' "$dst/cubegm/zhijack.sh"
    else
        sed -i -e '/#@R36@/d' -e 's/ #@HW@//' "$dst/cubegm/zhijack.sh"
    fi
    grep -q '@' "$dst/cubegm/zhijack.sh" && grep -o '@[A-Z_]*@' "$dst/cubegm/zhijack.sh" | sort -u | sed "s/^/  WARN[$dev]: unfilled /"
    chmod +x "$dst/cubegm/zhijack.sh"
    echo "  install_first/$dev ready"
done

# 3) Guide.
cat > "$OUT/INSTALL.md" <<'EOF'
# TreeFrogUI - install (R36SX / SF3000 / SF3500)

Unified boot: the stock menu (rkgame) auto-launches TreeFrogUI via a hijack core.
The stock boot files (icube, rkgame) are never modified, so SF3500's boot verifier
stays happy.

> [!CAUTION]
> # 🔴 **DO NOT USE THE FACTORY/PREINSTALLED STOCK OS** 🔴
>
> **Format the SD card and set it up fresh with the exact backup linked in
> `install.md`. This is not optional. Installing over the stock OS causes missing
> audio, broken controls, display problems, crashes, and boot failures.**

## Steps
1. **Format the SD card and perform a clean setup using the exact backup linked
   in `install.md` for your device.** Do not install over, reuse, or merge with
   the factory/preinstalled stock OS. If your card has an older TreeFrogUI that
   replaced `cubegm/icube`, the clean backup setup restores it.
2. Copy `cubegm/`, `frogui/`, `roms/`, `MD/` onto the SD root (merge/overwrite).
3. Copy the contents of **`install_first/<your-device>/`** onto the SD root too
   (REQUIRED: it carries the launcher script and autorun setup for your device):
   - `install_first/r36sx/`    → R36SX (v2.6 and v2.7 - same xml)
   - `install_first/sf3000/`   → SF3000
   - `install_first/sf3500/`   → SF3500
   - `install_first/sf3000hd/` → SF3000 HD (HDMI-out variant)
   - `install_first/sf3100/`   → SF3100
   - `install_first/gb350/`    → GB350
   (This sets the rkgame autorun + registers the hijack core for YOUR device.)
4. Eject, boot. The stock menu loads, then jumps straight into TreeFrogUI.

Diagnostics: `/mnt/sdcard/log.txt` (look for `=== zhijack boot`).

## Offline updates

Future releases include `update.zip`. Copy it directly to the SD-card root and
reboot. It is verified,
applied for this device and deleted only after success. Configs are refreshed
and their previous versions are backed up under `.treefrog-update/backup-<version>/`;
personal ROMs, BIOS files, saves, screenshots and media are not deleted.
EOF

# 4) FAT32 guard - the SD has no symlink support; fail loudly if any slipped in.
syms=$(find "$OUT" -type l)
if [ -n "$syms" ]; then echo "ERROR: symlinks in release (FAT32 can't store these):"; echo "$syms"; exit 1; fi

# 5) Release sanity checks - fail loudly instead of shipping a broken package.
fail() { echo "ERROR: $1"; exit 1; }
[ -f "$OUT/cubegm/zhijack.sh" ] && fail "payload must not ship a generic zhijack.sh"
[ -f "$OUT/cubegm/tf_detect.sh" ] && fail "payload must not ship tf_detect.sh (detection retired)"
# every device: boot block = freeze icube + kill rkgame (STOP no-ops without icube)
for dev in "${!STOCK[@]}"; do
    grep -q 'kill -STOP $(pidof icube)' "$OUT/install_first/$dev/cubegm/zhijack.sh" \
        || fail "$dev zhijack must SIGSTOP icube at boot"
done
# r36sx: boot killall only, no loop kills (tested config)
[ "$(grep -c 'killall rkgame' "$OUT/install_first/r36sx/cubegm/zhijack.sh")" = 1 ] \
    || fail "r36sx zhijack must contain exactly 1 killall rkgame (boot block only)"
for dev in sf3000 sf3500 sf3000hd sf3100 gb350; do
    [ "$(grep -c 'killall rkgame' "$OUT/install_first/$dev/cubegm/zhijack.sh")" = 3 ] \
        || fail "$dev zhijack must contain 3 killall rkgame (boot + 2 loop)"
done
for dev in "${!STOCK[@]}"; do
    [ -x "$OUT/install_first/$dev/cubegm/zhijack.sh" ] || fail "missing zhijack for $dev"
    [ -f "$OUT/install_first/$dev/cubegm/cores/$OVERRIDE_CORE" ] || fail "missing hijack core for $dev"
done
[ -f "$OUT/$DUMMY_REL" ] || fail "missing autorun dummy rom $DUMMY_REL"
[ -x "$OUT/cubegm/tfupdate.sh" ] || fail "missing offline updater"
grep -q 'sh /tmp/tfupdate.sh' "$OUT/install_first/sf3000/cubegm/zhijack.sh" \
    || fail "generated launchers do not invoke offline updater"

echo
echo "=== $OUT ready (FAT32-safe, no symlinks, sanity checks passed) ==="
du -sh "$OUT"
find "$OUT" -maxdepth 3 -type d | sort
echo
last=$(find "$RELEASE_ROOT/artifact" -maxdepth 1 -type f -name 'TreeFrogUI_v*.zip' \
    -printf '%f\n' 2>/dev/null | sort -V | tail -1)
echo "To package: ./pack_release.sh vX.Y.Z_?   (comparison artifact: ${last:-none})"
