#!/system/bin/sh
# G25 profiles: normal | demon | eco | next | status. No argument re-applies the saved profile;
# "next" cycles normal -> demon -> eco -> normal (used by the Quick Settings tile).
# Emergency-reset (sysrst) trips always stay armed, stricter in Demonio (TRIPS_DEMON).
# Never touched: charger JEITA, PPM low-battery limits, GPU battery/PBM limits.

# Always run under Magisk's busybox ash: the lock below needs its flock to inherit fd 9,
# and mksh (/system/bin/sh) opens exec'd fds close-on-exec.
[ -n "$G25_BB" ] || G25_BB=1 exec /data/adb/magisk/busybox sh "$0" "$@"

# Calibration knobs (Eco caps)
ECO_BIG_MAX=1484000     # cpu0-3, stock 2001000
ECO_LITTLE_MAX=1050000  # cpu4-7, stock 1500000
# Emergency-reset (sysrst) trips in millidegrees C: cpu battery board charger.
# Demonio uses the stricter set the user asked for; Normal/Eco restore stock.
TRIPS_STOCK="117000 60000 100000 120000"
TRIPS_DEMON="110000 55000 95000 110000"
# CFS latency / min granularity (ns). Low values measured 28% faster on a producer->consumer
# pipe (the emulator + render thread pattern): 1555 vs 2160 ms. Stock = ROM defaults.
CFS_DEMON="1000000 130000"
CFS_STOCK="10000000 3000000"
STOCK_GOV=schedplus  # governor the ROM sets at boot (the "interactive" seen before was LSpeed)
DEMON_KILL="com.android.chrome org.cromite.cromite com.stremio.one"
CPU=/sys/devices/system/cpu/cpufreq
TZ=/proc/driver/thermal

if [ "$1" = status ]; then
  echo "profile=$(settings get global g25_profile) battery_saver=$(settings get global low_power)"
  for p in 0 4; do
    echo "policy$p: $(cat $CPU/policy$p/scaling_governor) max=$(cat $CPU/policy$p/scaling_max_freq) cur=$(cat $CPU/policy$p/cpuinfo_cur_freq)"
  done
  echo "ppm caps: $(cat /proc/ppm/policy/hard_userlimit_max_cpu_freq | tr '\n' ' ')"
  echo "gpu: $(sed -n 2p /proc/gpufreq/gpufreq_var_dump) | $(cat /proc/gpufreq/gpufreq_opp_freq) | $(grep thermal /proc/gpufreq/gpufreq_power_limited)"
  echo "mi_thermald=$(getprop init.svc.mi_thermald) ppm_thermal=$(grep -o "THERMAL: [a-z]*" /proc/ppm/policy_status) fpsgo=$(cat /sys/kernel/debug/fpsgo/common/fpsgo_enable) cfp=$(cat /proc/perfmgr/boost_ctrl/cpu_ctrl/cfp_enable) system-background=$(cat /dev/cpuset/system-background/cpus) cfs=$(cat /proc/sys/kernel/sched_latency_ns)/$(cat /proc/sys/kernel/sched_min_granularity_ns)"
  grep -hE "sysrst|cpu_adaptive" $TZ/tzcpu $TZ/tzcharger
  grep -hoE "trip_0_temp=[0-9]+|cooldev0=[a-zA-Z-]+" $TZ/tzbattery $TZ/tzbts | tr '\n' ' '; echo
  exit
fi
# Demonio watchdog: the MTK cpufreq driver drops requests during suspend and "performance" never
# asks again, so a cluster was found stuck at 1208 MHz after hours of use. Re-kick when a
# cluster sits below its max (legit PPM battery limits just make this a harmless no-op).
if [ "$1" = kick ]; then
  while :; do
    for p in 0 4; do
      cur=$(cat $CPU/policy$p/cpuinfo_cur_freq); max=$(cat $CPU/policy$p/scaling_max_freq)
      if [ "$cur" -lt "$max" ]; then
        # Rewriting scaling_min_freq sends a limits event, so "performance" asks for max again
        # (rewriting the same governor name is a no-op in the cpufreq core).
        cat $CPU/policy$p/scaling_min_freq > $CPU/policy$p/scaling_min_freq
        log -t g25_kick "policy$p $cur < $max, re-kicked"
      fi
    done
    sleep 10
  done
fi
KICK_PID=/dev/g25_kick.pid

# One profile change at a time: concurrent tz* writes race in the MTK thermal driver and
# panic the kernel (seen at boot, when Magisk ran service.sh three times at once).
exec 9>/dev/g25_profile.lock
flock 9
# Log where system_server may write: cmd/am/settings hand it our stdout/stderr.
exec >/data/local/tmp/g25_profile.log 2>&1
set -x

w() { echo "$2" > "$1"; }
cpu() {  # governor big_max little_max (-1 = no cap). MTK PPM overrides scaling_max_freq,
         # so caps go through its hard user limit (cluster 0 = cpu0-3, 1 = cpu4-7).
  w $CPU/policy0/scaling_governor $1; w $CPU/policy4/scaling_governor $1
  w /proc/ppm/policy/hard_userlimit_max_cpu_freq "0 $2"
  w /proc/ppm/policy/hard_userlimit_max_cpu_freq "1 $3"
}
trips() {  # cpu battery board charger. Format from the dandelion kernel (mtk_ts_*.c): num_trip,
           # 10 x "temp type cooler", polling interval. Unused trips keep their stock values.
  w $TZ/tzcpu "2 $1 0 mtktscpu-sysrst 65000 0 cpu_adaptive_0 64000 0 no-cooler 63000 0 no-cooler 62000 0 no-cooler 60000 0 no-cooler 55000 0 no-cooler 50000 0 no-cooler 45000 0 no-cooler 40000 0 no-cooler 200"
  w $TZ/tzbattery "1 $2 0 mtktsbattery-sysrst 48000 0 no-cooler 46000 0 no-cooler 45000 0 no-cooler 44000 0 no-cooler 43000 0 no-cooler 42000 0 no-cooler 41000 0 no-cooler 40000 0 no-cooler 39000 0 no-cooler 1000"
  w $TZ/tzbts "1 $3 0 mtktsAP-sysrst 96000 0 no-cooler 95000 0 no-cooler 90000 0 no-cooler 80000 0 no-cooler 70000 0 no-cooler 65000 0 no-cooler 60000 0 no-cooler 55000 0 no-cooler 50000 0 no-cooler 1000"
  w $TZ/tzcharger "1 $4 0 mtktscharger-sysrst 110000 0 no-cooler 100000 0 no-cooler 90000 0 no-cooler 80000 0 no-cooler 70000 0 no-cooler 65000 0 no-cooler 60000 0 no-cooler 55000 0 no-cooler 50000 0 no-cooler 2000"
}
thermal() {  # off | stock. "off" = no MIUI daemon and no PPM thermal budget (MTK ATM
             # starts throttling at 65C through it); the tz* sysrst trips stay armed.
  if [ $1 = off ]; then
    stop mi_thermald
    w /proc/ppm/policy_status "4 0"
  else
    w /proc/ppm/policy_status "4 1"
    start mi_thermald
  fi
}
gpu() {  # fixed_khz (0 = DVFS) ignore_thermal (0/1). Writing 0 logs "Bad address" but works
         # (the driver's return value); check `status` for the real state.
  w /proc/gpufreq/gpufreq_opp_freq $1
  w /proc/gpufreq/gpufreq_power_limited "ignore_thermal_protect $2"
}
cfs() {  # sched_latency_ns sched_min_granularity_ns
  w /proc/sys/kernel/sched_latency_ns $1; w /proc/sys/kernel/sched_min_granularity_ns $2
}
helpers() {  # FPSGO and perfmgr CFP: 1 = stock, 0 = off
  w /sys/kernel/debug/fpsgo/common/fpsgo_enable $1
  w /proc/perfmgr/boost_ctrl/cpu_ctrl/cfp_enable $1
}

[ -f $KICK_PID ] && kill -9 "$(cat $KICK_PID)" 2>/dev/null; rm -f $KICK_PID  # stop Demonio's watchdog first

P=${1:-$(settings get global g25_profile)}
[ "$P" = next ] && case $(settings get global g25_profile) in demon) P=eco ;; eco) P=normal ;; *) P=demon ;; esac
case $P in
  demon)
    trips $TRIPS_DEMON; thermal off; cpu performance -1 -1; gpu 650000 1; helpers 0; cfs $CFS_DEMON
    w /dev/cpuset/system-background/cpus 4-7
    cmd power set-mode 0
    for p in $DEMON_KILL; do am force-stop $p; done
    setsid sh "$0" kick 9>&- </dev/null >/dev/null 2>&1 & echo $! > $KICK_PID ;;  # 9>&-: must not hold the lock
  eco)
    thermal stock; trips $TRIPS_STOCK; cpu $STOCK_GOV $ECO_BIG_MAX $ECO_LITTLE_MAX; gpu 400000 0; helpers 1; cfs $CFS_STOCK
    w /dev/cpuset/system-background/cpus 4-7
    cmd power set-mode 1 ;;
  *)
    P=normal
    thermal stock; trips $TRIPS_STOCK; cpu $STOCK_GOV -1 -1; gpu 0 0; helpers 1; cfs $CFS_STOCK
    w /dev/cpuset/system-background/cpus 2-7
    cmd power set-mode 0 ;;
esac
settings put global g25_profile $P
