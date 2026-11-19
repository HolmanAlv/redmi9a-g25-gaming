# Sustained CPU test, run as root on the phone: adb shell su < stress.sh > result.csv
# 8 busy loops for 10 min, sampling every 5 s; single-thread md5 bench cold and hot.
C=/sys/devices/system/cpu/cpufreq
t() { cat /sys/class/thermal/thermal_zone$1/temp; }   # 4=cpu, 0=battery, 1=AP
bench() { s=$(date +%s%N); dd if=/dev/zero bs=1M count=256 2>/dev/null | md5sum >/dev/null; e=$(date +%s%N); echo $(( (e-s)/1000000 )); }
echo "# battery=$(cat /sys/class/power_supply/battery/capacity)% status=$(cat /sys/class/power_supply/battery/status) gov=$(cat $C/policy0/scaling_governor)"
echo "# cold_ms=$(bench)"
PIDS=""
for i in 1 2 3 4 5 6 7 8; do (while :; do :; done) & PIDS="$PIDS $!"; done
echo "t_s,f0_khz,f4_khz,cpu_mC,bat_mC,ap_mC,gpu_khz,ppm_thermal,cfp_ceiled"
n=0
while [ $n -lt 120 ]; do
  echo "$((n*5)),$(cat $C/policy0/cpuinfo_cur_freq),$(cat $C/policy4/cpuinfo_cur_freq),$(t 4),$(t 0),$(t 1),$(grep -o 'g_cur_opp_freq = [0-9]*' /proc/gpufreq/gpufreq_var_dump | grep -o '[0-9]*$'),$(grep -o 'activate = [0-9]*' /proc/ppm/policy/thermal_limit | grep -o '[0-9]*$'),$(sed -n 2p /proc/perfmgr/boost_ctrl/cpu_ctrl/cfp_curr_stat | awk '{print $2}')"
  sleep 5; n=$((n+1))
done
kill $PIDS
echo "# hot_ms=$(bench)"
echo "# max_cpu_mC=$(t 4)"
