# G25 Gaming Profiles

**Three one-tap performance profiles for a budget Android phone, built and measured from the kernel up.**

A Magisk module and a tiny Quick Settings app that turn a Redmi 9A (MediaTek Helio G25, 2 GB RAM, Android 10) into a better emulation handheld: **Normal**, **Demonio** (maximum performance) and **Eco**. Every setting was chosen from measurements on the device, and every decision is written down in the [engineering log](progress.md).

![Android](https://img.shields.io/badge/Android-10-3ddc84?style=flat-square&logo=android&logoColor=white)
![Magisk](https://img.shields.io/badge/Magisk-module-00af9c?style=flat-square)
![Shell](https://img.shields.io/badge/POSIX%20sh-busybox-4eaa25?style=flat-square&logo=gnubash&logoColor=white)
![Java](https://img.shields.io/badge/Java-Quick%20Settings%20tile-e76f00?style=flat-square)
![SoC](https://img.shields.io/badge/SoC-MediaTek%20Helio%20G25-blue?style=flat-square)

## Results

Measured with the browser benchmark in [`bench/`](bench) (CPU, GPU, RAM and 5 minutes of combined stress per profile, with clocks and temperatures logged over adb):

| | Normal (stock) | **Demonio** | Eco |
|---|---|---|---|
| Response to a burst after idle (median) | 178 ms | **59 ms (3x faster)** | 178 ms |
| RAM allocation, ms per 32 MB | 43 | **23** | 53 |
| RAM copy bandwidth | 3330 MB/s | **3544 MB/s** | 2374 MB/s |
| Lowest big/little clock under load | 900 / 400 MHz | **2001 / 1500 MHz** | 900 / 400 MHz |
| GPU clock | 400-650 MHz | **650 MHz fixed** | 400 MHz |
| Max CPU temperature | 50.0 °C | 51.2 °C | **41.8 °C** |

Other measured gains:

- **Free RAM roughly doubled** after a clean boot (MemAvailable 345-470 MB before, 786-974 MB after), from removing 24 preinstalled apps and a leftover "speed" module.
- **28 % faster producer → consumer handoff** (1555 vs 2160 ms) with a lower CFS scheduler latency, the pattern an emulator thread feeding a render thread follows.
- **No thermal throttling** in 10 minutes of 8-core stress in Demonio: clocks pinned at 2.0 / 1.5 GHz, CPU peak 58 °C.
- **Hardware video decoding restored** (second module, below): the custom ROM had shipped none that worked.

## What each profile does

| | Normal | Demonio | Eco |
|---|---|---|---|
| CPU governor | ROM default (`schedplus`) | `performance` + a watchdog that re-kicks clusters stuck below max after suspend | `schedplus`, capped at 1.48 / 1.05 GHz through MediaTek PPM |
| GPU | DVFS | fixed 650 MHz, thermal limit ignored | fixed 400 MHz |
| Thermal | stock | MIUI thermal daemon and PPM thermal budget off; **emergency-reset trips stay armed and stricter** (CPU 110, battery 55, board 95, charger 110 °C) | stock |
| Scheduler | 10 ms / 3 ms | 1 ms / 0.13 ms | 10 ms / 3 ms |
| Background apps | cores 2-7 | little cores only (4-7), closes browsers | little cores only, battery saver |

Never touched: charger JEITA limits, low-battery CPU limits and GPU battery limits. The phone always keeps a way to protect itself.

## How it works

```
Quick Settings tile (Java, 1 class)
      │  su -c "profile.sh next"
      ▼
profile.sh ── writes sysfs/procfs: cpufreq, /proc/ppm, /proc/gpufreq,
      │       thermal zones, sched_*, cpusets; saves the choice in Settings.Global
      ▼
service.sh ── re-applies the saved profile 30 s after every boot
```

- [`module/g25_gaming/profile.sh`](module/g25_gaming/profile.sh): `normal | demon | eco | next | status`. Calibration values sit at the top of the file.
- [`module/g25_gaming/service.sh`](module/g25_gaming/service.sh): boot hook, single instance.
- [`app/`](app): the "G25 Profiles" tile. Built **without Gradle**: `javac` → `d8` → `aapt2` → `zipalign` → `apksigner` in [`build.sh`](app/build.sh); the APK is about 13 KB.
- [`bench/`](bench): `bench.html` (CPU workers, WebGL shader load, memory bandwidth, latency and pressure), a tiny Python server that receives results, `run.sh` to run it once per profile and `summarize.py` for the table above.
- [`tests/`](tests): sustained-load and post-reboot checks, with the raw CSVs before and after.

## Bugs found on the way

The hard part was the hardware, not the code. A few things the log records:

- **Kernel panic from parallel writes.** Magisk ran the boot hook three times at once on this ROM, and concurrent writes to the MediaTek thermal driver panicked the kernel. Fix: an atomic `mkdir` lock for the boot hook and `flock` around every profile change.
- **MediaTek PPM silently overrides `scaling_max_freq`.** CPU caps only hold through `/proc/ppm/policy/hard_userlimit_max_cpu_freq`, verified under load.
- **The cpufreq driver drops requests during suspend,** leaving a cluster stuck at 1208 MHz in `performance`. Fix: a watchdog that rewrites `scaling_min_freq`, which makes the governor ask for max again.
- **An earlier diagnosis was wrong,** and the log says so: the old "speed" module's low scheduler latency did help, measured in isolation, so Demonio keeps it.
- **A mass `pm uninstall` burst** tripped a system_server watchdog restart; apps were then removed one at a time.
- **Android 10's `dex2oat` crashes** compiling two emulators with the `speed` filter; they use `quicken`.

## Second module: hardware video decoding (`nad_hwcodec_fix`)

The custom ROM (Nusantara, Android 10) ships V4L2 video decoders for other MediaTek chips, which this kernel (legacy `/dev/Vcodec`) cannot run, so every app fell back to software decoding. The module puts MIUI's own decoder back: `libMtkOmxVdecEx.so` and `mtk_omx_core.cfg`.

Those two files are proprietary and **not included**. Copy them from your phone's stock MIUI `vendor` partition into `module/nad_hwcodec_fix/system/vendor/lib/` and `system/vendor/etc/`.

## Install

1. Rooted Redmi 9A (codename dandelion) with Magisk.
2. Zip each folder under `module/` and install it from Magisk, then reboot.
3. Build the tile with `app/build.sh` (needs a JDK, Android build-tools 35 and the android-35 `android.jar` in `tools/`), install the APK, add the "Perfil" tile and grant root when Magisk asks.
4. Or from a root shell: `sh /data/adb/modules/g25_gaming/profile.sh demon` (`status` shows the live state).

> **Warning:** this changes thermal and clock behavior on one specific phone. The thresholds are for the Helio G25 in a Redmi 9A. Do not run it on other devices.

## Methodology

Spec first, then a phased plan (baseline → debloat → profiles → tile → reboot verification), with a backup before every change and every decision logged with the cost of being wrong. Built with AI assistance (Claude Code) driving adb; every number above comes from the device logs in this repo.
