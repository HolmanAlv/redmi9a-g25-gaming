#!/usr/bin/env python3
"""Compare bench results per profile: OUT/<profile>.jsonl (page) + OUT/<profile>-thermal.csv (adb logger)."""
import csv
import json
import pathlib
import sys

OUT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "results")
ORDER = ["normal", "demon", "eco"]


def load(profile):
    phases = {}
    for line in open(OUT / f"{profile}.jsonl"):
        rec = json.loads(line)
        phases[rec["phase"]] = rec
    thermal_file = OUT / f"{profile}-thermal.csv"
    thermal = list(csv.DictReader(open(thermal_file))) if thermal_file.exists() else []
    return phases, thermal


def row(p, t):
    get = lambda phase, key, fmt="{:.0f}": fmt.format(p[phase][key]) if key in p.get(phase, {}) else "-"
    series = p.get("sustained", {}).get("series", [])
    sus = lambda k: (f"{series[0][k]:.0f} → {series[-1][k]:.0f} ({100 * (series[-1][k] / series[0][k] - 1):+.0f}%)"
                     if len(series) > 1 else "-")
    col = lambda k: [int(r[k]) for r in t if r[k].isdigit()]
    return {
        "CPU 1 core (ops/s)": get("cpu_single", "ops_s", "{:.1f}"),
        "CPU 8 cores (ops/s)": get("cpu_multi", "ops_s", "{:.1f}"),
        "Burst after idle (ms, median/worst)": f"{get('burst', 'median_ms')} / {get('burst', 'max_ms')}",
        "RAM copy (MB/s)": get("mem_bw", "copy_mb_s"),
        "RAM latency (ns)": get("mem_latency", "ns", "{:.0f}"),
        "GPU (passes/s)": get("gpu", "passes_s", "{:.1f}"),
        "GPU (Mpix/s)": get("gpu", "mpix_s"),
        "Sustained GPU passes/s, first → last": sus("gpu_ps"),
        "Sustained CPU ops/s, first → last": sus("cpu_ops_s"),
        "Max CPU temp (C)": f"{max(col('cpu_mC')) / 1000:.1f}" if t else "-",
        "Max battery temp (C)": f"{max(col('bat_mC')) / 1000:.1f}" if t else "-",
        "Min f0 / f4 under test (MHz)": f"{min(col('f0_khz')) // 1000} / {min(col('f4_khz')) // 1000}" if t else "-",
        "GPU MHz seen": f"{min(col('gpu_khz')) // 1000}-{max(col('gpu_khz')) // 1000}" if t else "-",
        "PPM thermal limiting (samples)": str(sum(r["ppm_thermal"] == "1" for r in t)) if t else "-",
        "RAM pressure reached (MB)": get("ram_pressure", "reached_mb"),
        "RAM commit ms per 32 MB (median)": get("ram_pressure", "alloc_ms_per_32mb"),
        "RAM re-read all (ms)": get("ram_pressure", "reread_ms"),
    }


profiles = [p for p in ORDER if (OUT / f"{p}.jsonl").exists()] + \
           sorted(f.stem for f in OUT.glob("*.jsonl") if f.stem not in ORDER)
rows = {p: row(*load(p)) for p in profiles}
print("| Metric | " + " | ".join(profiles) + " |")
print("|---|" + "---|" * len(profiles))
for metric in next(iter(rows.values())):
    print(f"| {metric} | " + " | ".join(rows[p][metric] for p in profiles) + " |")
