# Post-reboot state, run as root: adb shell su < post-reboot-check.sh
# Run it right after sys.boot_completed to see stock values before service.sh applies the profile (+30 s).
C=/sys/devices/system/cpu/cpufreq
echo "uptime_s=$(cut -d' ' -f1 /proc/uptime) profile_log=$(ls -l /data/local/tmp/g25_profile.log 2>/dev/null | awk '{print $6, $7}')"
echo "gov0=$(cat $C/policy0/scaling_governor) gov4=$(cat $C/policy4/scaling_governor)"
for g in top-app foreground background system-background restricted; do echo "cpuset/$g=$(cat /dev/cpuset/$g/cpus)"; done
for f in swappiness vfs_cache_pressure min_free_kbytes extra_free_kbytes; do echo "vm/$f=$(cat /proc/sys/vm/$f)"; done
for f in sched_latency_ns sched_min_granularity_ns sched_wakeup_granularity_ns sched_migration_cost_ns; do echo "kernel/$f=$(cat /proc/sys/kernel/$f)"; done
echo "heapsize=$(getprop dalvik.vm.heapsize) heapgrowthlimit=$(getprop dalvik.vm.heapgrowthlimit) bg_apps_limit=$(getprop ro.sys.fw.bg_apps_limit)"
echo "mmcblk0 scheduler=$(cat /sys/block/mmcblk0/queue/scheduler) read_ahead_kb=$(cat /sys/block/mmcblk0/queue/read_ahead_kb)"
grep MemAvailable /proc/meminfo
