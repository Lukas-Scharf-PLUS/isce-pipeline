#!/usr/bin/env bash
set -euo pipefail

RUN_ENV="${1:?Usage: $0 conf/runs/<run_id>/run.env}"
source conf/stack.env
source "${RUN_ENV}"

mkdir -p "${ORBITS_DIR}" "${LOG_DIR}"

# .env laden
set -a
source .env
set +a

if [[ -z "${CDSE_USERNAME:-}" || -z "${CDSE_PASSWORD:-}" ]]; then
  echo "CDSE_USERNAME/CDSE_PASSWORD fehlen. Bitte .env prüfen."
  exit 1
fi

if [[ ! -d "${SLC_DIR}" ]]; then
  echo "SLC_DIR nicht gefunden: ${SLC_DIR}"
  exit 1
fi

python_range=$(uv run python - <<PY
from pathlib import Path
from datetime import datetime, timedelta
import re

slc_dir = Path("${SLC_DIR}")
names = []

for p in slc_dir.iterdir():
    if p.name.startswith("S1") and (p.name.endswith(".SAFE") or p.name.endswith(".zip")):
        names.append(p.name)

date_re = re.compile(r'_(\d{8})T\d{6}_')
dates = []

for name in names:
    m = date_re.search(name)
    if m:
        dates.append(datetime.strptime(m.group(1), "%Y%m%d"))

if not dates:
    raise SystemExit("Keine Sentinel-1 SAFE/ZIP-Dateien in SLC_DIR gefunden.")

start = (min(dates) - timedelta(days=1)).strftime("%Y%m%d")
end   = (max(dates) + timedelta(days=2)).strftime("%Y%m%d")
print(start, end)
PY
)

read -r start end <<< "${python_range}"

echo "RUN_ID     : ${RUN_ID}"
echo "SLC_DIR    : ${SLC_DIR}"
echo "ORBITS_DIR : ${ORBITS_DIR}"
echo "Orbit range: ${start} -> ${end}"

docker compose run --rm -T \
  -e CDSE_USERNAME \
  -e CDSE_PASSWORD \
  isce bash -lc "
    set -euo pipefail
    mkdir -p /workspace/${ORBITS_DIR}
    dloadOrbits.py \
      --start ${start} \
      --end ${end} \
      --dir /workspace/${ORBITS_DIR} \
      --username \"\$CDSE_USERNAME\" \
      --password \"\$CDSE_PASSWORD\"
  " 2>&1 | tee "${LOG_DIR}/21_fetch_orbits.log"