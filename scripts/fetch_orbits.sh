#!/bin/bash
set -e

echo "=== Fetching Sentinel-1 orbit files ==="

# =====================================================
# === INPUT PARAMETERS ================================
# =====================================================

SLC_DIR=${SLC_DIR:?ERROR: SLC_DIR not set}
ORB_DIR=${ORB_DIR:?ERROR: ORB_DIR not set}

CDSE_USERNAME=${CDSE_USERNAME:?Need CDSE_USERNAME}
CDSE_PASSWORD=${CDSE_PASSWORD:?Need CDSE_PASSWORD}

mkdir -p "$ORB_DIR"

echo "SLC_DIR: $SLC_DIR"
echo "ORB_DIR: $ORB_DIR"

# =====================================================
# === DETERMINE DATE RANGE ============================
# =====================================================

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