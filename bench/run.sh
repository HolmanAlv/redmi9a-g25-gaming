#!/bin/bash
# Run bench.html in Chrome on the phone once per profile, logging freqs/temps over adb.
# Usage: ./run.sh [results-dir]   env: PROFILES="normal demon eco" SUSTAIN=300 MEMMAX=512
set -e
cd "$(dirname "$0")"
# One phone connected, or pick it with ANDROID_SERIAL (adb reads it).
OUT=${1:-results}
PROFILES=${PROFILES:-normal demon eco}
COOL_MC=45000  # start each profile with the CPU below 45 C
mkdir -p "$OUT"

python3 server.py "$OUT" & SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
adbreverse tcp:8765 tcp:8765 >/dev/null

cpu_temp() { adbshell su -c "'cat /sys/class/thermal/thermal_zone4/temp'" | tr -d '\r'; }

for P in $PROFILES; do
  echo "== $P: cooling down (CPU $(cpu_temp))"
  for i in $(seq 60); do [ "$(cpu_temp)" -lt $COOL_MC ] && break; sleep 10; done
  adbshell su -c "'sh /data/adb/modules/g25_gaming/profile.sh $P'"
  rm -f "$OUT/$P.jsonl"
  adbshell su > "$OUT/$P-thermal.csv" <<'EOF' &
C=/sys/devices/system/cpu/cpufreq; Z=/sys/class/thermal; STOP=/data/local/tmp/g25_bench.stop
rm -f $STOP
echo "t_s,f0_khz,f4_khz,gpu_khz,cpu_mC,bat_mC,ap_mC,ppm_thermal"
s=$(cut -d. -f1 /proc/uptime)
while [ ! -e $STOP ]; do
  echo "$(( $(cut -d. -f1 /proc/uptime) - s )),$(cat $C/policy0/cpuinfo_cur_freq),$(cat $C/policy4/cpuinfo_cur_freq),$(grep -o 'g_cur_opp_freq = [0-9]*' /proc/gpufreq/gpufreq_var_dump | grep -o '[0-9]*$'),$(cat $Z/thermal_zone4/temp),$(cat $Z/thermal_zone0/temp),$(cat $Z/thermal_zone1/temp),$(grep -o 'activate = [0-9]*' /proc/ppm/policy/thermal_limit | grep -o '[0-9]*$')"
  sleep 5
done
EOF
  LOG=$!
  adbshell am start -a android.intent.action.VIEW -n com.android.chrome/com.google.android.apps.chrome.Main \
    -d "'http://localhost:8765/bench.html?profile=$P&sustain=${SUSTAIN:-300}&memmax=${MEMMAX:-512}'" >/dev/null
  timeout 1500 bash -c "until grep -q '\"phase\": \"done\"' '$OUT/$P.jsonl' 2>/dev/null; do sleep 5; done" \
    || echo "$P: timed out (page crashed or stuck)"
  adbshell su -c "'touch /data/local/tmp/g25_bench.stop'"; wait $LOG
  adbshell am force-stop com.android.chrome
done
python3 summarize.py "$OUT"
