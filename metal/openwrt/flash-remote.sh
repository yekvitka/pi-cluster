#!/bin/bash
# Write an OpenWrt image over the SD card of a running Raspberry Pi (Linux, root SSH)
#
#   metal/openwrt/flash-remote.sh root@192.168.50.200 metal/openwrt/img/openwrt-<version>-gateway.img
#
# DESTRUCTIVE: the target's SD card is overwritten and the Pi reboots into OpenWrt.
# If it does not come back, remove the SD card and write the same image with dd.

set -euo pipefail

HOST="${1:?usage: $0 <ssh host> <image>}"
IMAGE="${2:?usage: $0 <ssh host> <image>}"
DISK="${DISK:-/dev/mmcblk0}"
REMOTE_IMAGE="/dev/shm/openwrt.img"

model="$(ssh "$HOST" 'tr -d "\0" < /proc/device-tree/model')"
root_disk="$(ssh "$HOST" 'lsblk -no PKNAME "$(findmnt -no SOURCE /)"')"
echo "[INFO] Target: $HOST, $model, root on /dev/$root_disk"
case "$model" in
  "Raspberry Pi 4"*) ;;
  *) echo "[ERROR] Not a Raspberry Pi 4" >&2; exit 1 ;;
esac
[ "/dev/$root_disk" = "$DISK" ] || { echo "[ERROR] Root disk is not $DISK" >&2; exit 1; }

echo "[INFO] Copying image to $HOST:$REMOTE_IMAGE"
ssh "$HOST" "cat > $REMOTE_IMAGE" < "$IMAGE"
local_sum="$(sha256sum "$IMAGE" | awk '{print $1}')"
remote_sum="$(ssh "$HOST" "sha256sum $REMOTE_IMAGE" | awk '{print $1}')"
[ "$local_sum" = "$remote_sum" ] || { echo "[ERROR] Checksum mismatch after copy" >&2; exit 1; }

# Detached from the SSH session, so a dropped connection cannot stop dd halfway.
# Root is remounted read-only first, then the Pi reboots right after the write.
echo "[INFO] Writing $DISK and rebooting"
ssh "$HOST" "setsid sh -c 'sync; echo 1 > /proc/sys/kernel/sysrq; echo u > /proc/sysrq-trigger; \
  dd if=$REMOTE_IMAGE of=$DISK bs=4M conv=fsync; sync; echo b > /proc/sysrq-trigger' \
  > /dev/null 2>&1 < /dev/null &"
echo "[INFO] Done. OpenWrt should answer on 10.0.0.1 in 1-2 minutes"
