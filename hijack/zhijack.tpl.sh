#!/bin/sh
# zhijack.sh for @DEV_LABEL@ — GENERATED from hijack/zhijack.tpl.sh by
# build_release.sh. Do not edit on the SD; edit the template and regenerate.
#
# Reached via stock boot: rkgame (verified, untouched) -> setting.xml autorun ->
# libemu_tfhijack.so forks this script (rkgame stays alive, keeping the
# cubevol gpio -> /tmp/joy_key input pipeline up). Everything device-specific
# is HARDCODED below — no runtime device detection. /tmp/tfdevice.env is still
# written because picoarch and the standalone frontends (pcsx4all, lgpt,
# pico286) read it.
mkdir /tmp/zhijack.lock 2>/dev/null || exit 0

# Never inherit the stock launcher's SD-card working directory.  USB mode
# must unmount /mnt/sdcard before exporting its block device; a shell (or
# child launcher) whose cwd is on that filesystem makes umount fail with
# EBUSY even after the UI has exited.
cd / || exit 1

# Re-exec the launcher from RAM.  BusyBox ash keeps the file descriptor for
# the script it is interpreting; if this remains the SD copy, USB mode cannot
# unmount the card even after all child processes exit.
if [ "${TF_ZHIJACK_RAM:-0}" != 1 ]; then
    cp "$0" /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    chmod 700 /tmp/treefrog-zhijack.sh 2>/dev/null || exit 1
    # The RAM copy must be able to reacquire the single-instance lock.
    rm -rf /tmp/zhijack.lock 2>/dev/null
    TF_ZHIJACK_RAM=1 exec /bin/sh /tmp/treefrog-zhijack.sh
    exit 1
fi

# Diagnostics are OPT-IN so we don't chew the SD card in normal use: logging is
# ON only if the user pre-created /mnt/sdcard/log.txt. Otherwise LOG=/dev/null and
# every write below is a no-op (and picoarch's own dbg_log is gated the same way,
# on log.txt existing). To debug: drop an empty log.txt on the card and reboot.
if [ -f /mnt/sdcard/log.txt ]; then
    LOG=/mnt/sdcard/log.txt
    mv "$LOG" "$LOG.prev" 2>/dev/null
    : > "$LOG"
    echo "=== zhijack boot [@DEV_LABEL@] $(date '+%H:%M:%S' 2>/dev/null) ===" >> "$LOG"
    sync
else
    LOG=/dev/null
fi

# Offline updates: users drop the official update.zip into the SD-card root.
# Run a /tmp copy so the updater can atomically replace its own
# installed file. Status 10 means success: restart through the newly installed
# device launcher. Failures keep both the current installation and update ZIP.
if [ -f /mnt/sdcard/cubegm/tfupdate.sh ]; then
    cp /mnt/sdcard/cubegm/tfupdate.sh /tmp/tfupdate.sh 2>/dev/null
    if [ -f /tmp/tfupdate.sh ]; then
        sh /tmp/tfupdate.sh @DEV_LABEL@
        UPDATE_RC=$?
        if [ "$UPDATE_RC" = 10 ]; then
            echo "offline update installed; restarting launcher" >> "$LOG"
            rm -rf /tmp/zhijack.lock
            exec /mnt/sdcard/cubegm/zhijack.sh
            exit 1
        elif [ "$UPDATE_RC" != 0 ]; then
            echo "offline update failed rc=$UPDATE_RC; continuing current version" >> "$LOG"
        fi
    fi
fi

# Freeze icube (the respawner), THEN kill rkgame. Devices that boot through
# icube (R36SX, SF3000, GB350) respawn any killed rkgame, and the fresh
# instance redraws the stock menu over our frames (flicker/ghosting); a merely
# frozen rkgame (SIGSTOP) glitched the display too. Frozen icube = no respawn;
# dead rkgame = nothing reacting to SELECT+START (its stock exit-game hotkey).
# On rkgame-direct devices (SF3500/HD/SF3100) there is no icube: STOP no-ops.
kill -STOP $(pidof icube) 2>/dev/null
killall rkgame 2>/dev/null
echo "icube frozen, rkgame killed" >> "$LOG"

cat > /tmp/tfdevice.env <<EOF
TF_DEVICE=@DEV@
TF_PANEL_W=@PW@
TF_PANEL_H=@PH@
TF_UI_SCALE=150
TF_ASPECT_NUM=@ASPN@
TF_ASPECT_DEN=@ASPD@
TF_ROTATE=@ROT@
TF_PRESENT=@PRESENT@
TF_DRIVER=/mnt/sdcard/cubegm/@DRIVER@
EOF
export TF_DEVICE=@DEV@ TF_PANEL_W=@PW@ TF_PANEL_H=@PH@ TF_UI_SCALE=150

# Some "SF3000"-branded units are really SF3500-class hardware (the "v3" / HDMI
# variant): same 854x480 panel geometry, but the SF3500 audio+display driver. The
# reliable tell is the stock driver.so format: classic SF3000 ships a PLAIN ELF
# driver, SF3500-class ships an ENCRYPTED one. If we're booting as SF3000 but the
# stock driver is encrypted, switch to driver_sf3500.so. Otherwise the classic
# SF3000 driver's audio (AUDDEC/I2SO) init fails on this hardware and picoarch
# SIGSEGVs on the NULL sound handle (+0x270) → black-screen boot loop.
if [ "$TF_DEVICE" = SF3000 ] && [ -f /mnt/sdcard/cubegm/driver_sf3500.so ] && \
   [ "$(head -c4 /mnt/sdcard/cubegm/driver.so 2>/dev/null)" != "$(printf '\177ELF')" ]; then
    sed -i -e 's/^TF_DEVICE=.*/TF_DEVICE=SF3500/' \
           -e 's|^TF_DRIVER=.*|TF_DRIVER=/mnt/sdcard/cubegm/driver_sf3500.so|' /tmp/tfdevice.env
    export TF_DEVICE=SF3500
    echo "SF3000 with encrypted (SF3500-class) driver detected → using driver_sf3500.so" >> "$LOG"
fi

# R36SX driver self-selection. Some kernels (v2.7-class, but firmware traits    #@R36@
# vary WITHIN 2.6/2.7, so no offline identification works) make the full v2.6   #@R36@
# driver SIGBUS in hcge_open. Measure instead of guessing: run the full driver; #@R36@
# if frogui dies with SIGBUS twice, switch permanently (marker file on SD) to   #@R36@
# driver_r36sx27.so, the variant with the crashing 2D engine stubbed out.       #@R36@
DRV_SAFE=/mnt/sdcard/cubegm/driver_r36sx27.so #@R36@
DRV_FLAG=/mnt/sdcard/cubegm/driver27.flag #@R36@
SIGBUS_N=0 #@R36@
if [ -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then #@R36@
    sed -i "s|^TF_DRIVER=.*|TF_DRIVER=$DRV_SAFE|" /tmp/tfdevice.env #@R36@
    echo "driver: SAFE variant (previous boots hit SIGBUS)" >> "$LOG" #@R36@
fi #@R36@

echo "processes at boot:" >> "$LOG"; ps >> "$LOG" 2>&1; [ "$LOG" = /dev/null ] || sync

export LD_LIBRARY_PATH=/mnt/sdcard/cubegm/lib:/mnt/sdcard/cubegm/usr/lib:$LD_LIBRARY_PATH

# CPU: force max-performance governor (helps every emulator).
for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -w "$g" ] && echo performance > "$g" 2>/dev/null
done
for c in /sys/devices/system/cpu/cpu*/cpufreq; do
    mx=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)
    [ -n "$mx" ] && [ -w "$c/scaling_min_freq" ] && echo "$mx" > "$c/scaling_min_freq" 2>/dev/null
done
if [ "$LOG" != /dev/null ]; then
    echo "CPU frequency policy after performance request:" >> "$LOG"
    for c in /sys/devices/system/cpu/cpu*/cpufreq; do
        echo "$c governor=$(cat "$c/scaling_governor" 2>/dev/null) cur=$(cat "$c/scaling_cur_freq" 2>/dev/null) min=$(cat "$c/scaling_min_freq" 2>/dev/null) max=$(cat "$c/scaling_max_freq" 2>/dev/null) hwmax=$(cat "$c/cpuinfo_max_freq" 2>/dev/null)" >> "$LOG"
    done
fi

# Input: cubevol (reads gpio -> /tmp/joy_key shm) must be up; picoarch reads the shm.
pidof cubevol >/dev/null 2>&1 || { [ -x /usr/bin/cubevol ] && /usr/bin/cubevol & }
sleep 0.5

# Optional: disable the power-button sleep (FrogUI Settings -> "Disable Sleep",
# default off, applies after restart). Live-patch every cubevol instance in RAM
# so the on-disk binary stays byte-identical -> passes SF3500 boot verification.
# The watcher also handles a genuine daemon crash/respawn. @NOSLEEP@ is the
# per-device set of validated sleep-arm text addresses (empty = device not
# supported). Long-press power-off is a separate path, untouched.
TF_NOSLEEP_ADDRS="@NOSLEEP@"
if [ -n "$TF_NOSLEEP_ADDRS" ] && grep -q '^disable_sleep=on' /mnt/sdcard/frogui/settings.txt 2>/dev/null; then
    echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>/dev/null
    [ -f /mnt/sdcard/cubegm/nosleep ] && /mnt/sdcard/cubegm/nosleep -w $TF_NOSLEEP_ADDRS >/dev/null 2>&1 &
fi

PICOARCH=/mnt/sdcard/cubegm/picoarch
PICOARCH_HI=/mnt/sdcard/cubegm/picoarch_hi
FROGUI_CORE=/mnt/sdcard/cubegm/cores/frogui_libretro.so
LAUNCH=/tmp/frogui_launch.txt

ITER=0
while true; do
    ITER=$((ITER+1))
    rm -f "$LAUNCH"
    killall rkgame 2>/dev/null #@KILL@
    echo "--- iter $ITER: frogui ---" >> "$LOG"
    # Keep child stdout off the SD.  USB mode must be able to unmount even
    # when diagnostics are enabled via /mnt/sdcard/log.txt.
    "$PICOARCH" "$FROGUI_CORE" "$FROGUI_CORE" >> /tmp/treefrog_ui.log 2>&1
    RC=$?
    echo "frogui exited rc=$RC" >> "$LOG"
    # SIGBUS in the menu with the full driver → count, and after 2 strikes    #@R36@
    # flip to the safe driver for this and every future boot.                 #@R36@
    if [ "$RC" = 138 ] && [ ! -f "$DRV_FLAG" ] && [ -f "$DRV_SAFE" ]; then #@R36@
        SIGBUS_N=$((SIGBUS_N+1)) #@R36@
        if [ "$SIGBUS_N" -ge 2 ]; then #@R36@
            touch "$DRV_FLAG" #@R36@
            sed -i "s|^TF_DRIVER=.*|TF_DRIVER=$DRV_SAFE|" /tmp/tfdevice.env #@R36@
            echo "driver: 2x SIGBUS with full driver → switching to SAFE variant permanently" >> "$LOG" #@R36@
            sync #@R36@
        fi #@R36@
    fi #@R36@

    if [ -f "$LAUNCH" ]; then
        LAUNCH_KIND=$(sed -n '1p' "$LAUNCH")
        if [ "$LAUNCH_KIND" = standalone ]; then
            BIN_PATH=$(sed -n '2p' "$LAUNCH")
            ARG_PATH=$(sed -n '3p' "$LAUNCH")
            rm -f "$LAUNCH"
            sleep 0.3
            echo "--- iter $ITER: standalone [$BIN_PATH] ---" >> "$LOG"
            if [ -n "$ARG_PATH" ]; then
                "$BIN_PATH" "$ARG_PATH" >> /tmp/treefrog_ui.log 2>&1
            else
                "$BIN_PATH" >> /tmp/treefrog_ui.log 2>&1
            fi
            sleep 0.2
            continue
        fi
        CORE_PATH=$(sed -n '1p' "$LAUNCH")
        killall rkgame 2>/dev/null #@KILL@
        ROM_PATH=$(sed -n '2p' "$LAUNCH")
        rm -f "$LAUNCH"
        if [ -n "$CORE_PATH" ] && [ -n "$ROM_PATH" ]; then
            sleep 0.3
            BIN="$PICOARCH"
            case "$CORE_PATH" in
                *gpsp*|*pcsx*|*ps1*|*ppsspp*) [ -f "$PICOARCH_HI" ] && BIN="$PICOARCH_HI" ;;
            esac
            echo "--- iter $ITER: game [$CORE_PATH] via $BIN ---" >> "$LOG"
            echo "launcher pid=$$ exe=$(readlink /proc/$$/exe 2>/dev/null)" >> "$LOG"
            echo "bin stat: $(ls -l "$BIN" 2>/dev/null)" >> "$LOG"
            echo "core stat: $(ls -l "$CORE_PATH" 2>/dev/null)" >> "$LOG"
            echo "rom stat: $(ls -l "$ROM_PATH" 2>/dev/null)" >> "$LOG"
            echo "device env: $(tr '\n' ' ' < /tmp/tfdevice.env 2>/dev/null)" >> "$LOG"
            echo "pre-game ps:" >> "$LOG"; ps >> "$LOG" 2>&1
            # Record the exact child executable/PID; stock rkgame and the
            # TreeFrogUI child can otherwise produce indistinguishable driver
            # messages in the shared log.
            "$BIN" "$CORE_PATH" "$ROM_PATH" >> /tmp/treefrog_ui.log 2>&1 &
            GAME_PID=$!
            GAME_EXE=$(readlink "/proc/$GAME_PID/exe" 2>/dev/null)
            echo "game pid=$GAME_PID exe=$GAME_EXE" >> "$LOG"
            echo "game cmdline: $(tr '\0' ' ' < /proc/$GAME_PID/cmdline 2>/dev/null)" >> "$LOG"
            echo "game status: $(tr '\n' ' ' < /proc/$GAME_PID/status 2>/dev/null)" >> "$LOG"
            wait "$GAME_PID"
            GRC=$?
            echo "game exited rc=$GRC" >> "$LOG"
        fi
    fi
    sleep 0.2
done
