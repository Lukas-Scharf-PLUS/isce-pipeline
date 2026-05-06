#!/bin/bash
set -euo pipefail

echo "=== Fetching Sentinel-1 orbit files ==="

# =====================================================
# === INPUT PARAMETERS ================================
# =====================================================

ORB_DIR=${ORB_DIR:?ERROR: ORB_DIR not set}

CDSE_USERNAME=${CDSE_USERNAME:?Need CDSE_USERNAME}
CDSE_PASSWORD=${CDSE_PASSWORD:?Need CDSE_PASSWORD}

# Optional inputs
SLC_DIR=${SLC_DIR:-""}
START_DATE=${START_DATE:-""}
END_DATE=${END_DATE:-""}

mkdir -p "$ORB_DIR"

echo "ORB_DIR: $ORB_DIR"

# =====================================================
# === DETERMINE DATE RANGE ============================
# =====================================================

if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    echo "Using provided date range"
else
    echo "No START_DATE/END_DATE provided → deriving from SLC_DIR"

    if [[ -z "$SLC_DIR" ]]; then
        echo "ERROR: Either START_DATE/END_DATE OR SLC_DIR must be provided"
        exit 1
    fi

    if [[ ! -d "$SLC_DIR" ]]; then
        echo "ERROR: SLC_DIR does not exist: $SLC_DIR"
        exit 1
    fi

    python_range=$(python3 - <<EOF
from pathlib import Path
from datetime import datetime, timedelta
import re

slc_dir = Path("$SLC_DIR")

date_re = re.compile(r'_(\d{8})T\d{6}_')
dates = []

for p in slc_dir.rglob("*"):
    if p.name.startswith("S1") and (p.name.endswith(".SAFE") or p.name.endswith(".zip")):
        m = date_re.search(p.name)
        if m:
            dates.append(datetime.strptime(m.group(1), "%Y%m%d"))

if not dates:
    raise SystemExit("No Sentinel-1 SLC files found.")

start = (min(dates) - timedelta(days=1)).strftime("%Y%m%d")
end   = (max(dates) + timedelta(days=2)).strftime("%Y%m%d")

print(start, end)
EOF
    )

    read -r START_DATE END_DATE <<< "$python_range"
fi

echo "Orbit range: $START_DATE → $END_DATE"

# =====================================================
# === DOWNLOAD ORBITS ================================
# =====================================================

dloadOrbits.py \
  --start "$START_DATE" \
  --end "$END_DATE" \
  --dir "$ORB_DIR" \
  --username "$CDSE_USERNAME" \
  --password "$CDSE_PASSWORD"

echo "=== Orbit download complete ==="