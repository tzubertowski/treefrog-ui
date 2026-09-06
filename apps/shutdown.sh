#!/bin/sh
sync
sleep 1
if command -v poweroff >/dev/null 2>&1; then
    poweroff -f 2>/dev/null || poweroff
elif [ -x /sbin/poweroff ]; then
    /sbin/poweroff -f 2>/dev/null || /sbin/poweroff
elif [ -x /bin/busybox ]; then
    /bin/busybox poweroff -f 2>/dev/null || /bin/busybox poweroff
else
    /sbin/reboot -p
fi
