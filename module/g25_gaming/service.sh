#!/system/bin/sh
# Re-apply the saved profile after boot.
MODDIR=${0%/*}
# Magisk runs late_start service three times on this ROM: only the first instance goes on.
mkdir /dev/g25_service.once 2>/dev/null || exit 0
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
sleep 30  # let vendor init and the power HAL settle
# zram-friendly on 1.8 GB RAM: kernel caps this at 100; the ROM's memcg 150 holds no tasks.
echo 100 > /proc/sys/vm/swappiness
sh "$MODDIR/profile.sh"
