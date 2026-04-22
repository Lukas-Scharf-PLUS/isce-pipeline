#!/bin/bash
set -e

echo "=== ISCE stackSentinel pipeline (inside container) ==="

# =====================================================
# === PARSE REQUIRED CLI ARGUMENTS =====================
# =====================================================

if [ "$#" -lt 4 ]; then
  echo "Usage:"
  echo "  $0 <DATA_DIR> <ORB_DIR> <DEM> <AUX_DIR> [options]"
  echo ""
  echo "Example:"
  echo "  $0 /data/ASF_SLC /data/orbits /data/dem.dem /data/aux -b \"48 49 16 17\""
  exit 1
fi

DATA_DIR=$1
ORB_DIR=$2
DEM=$3
AUX_DIR=$4

shift 4

# =====================================================
# === DEFAULT PARAMETERS ===============================
# =====================================================

BBOX="48.17229133 48.2238674 16.34362814 16.37115647"
REF_DATE="20200616"

C=2
Z=2
R=6
F=0.5
NUM_PROC=3
OMP_THREADS=2

# =====================================================
# === OPTIONAL CLI FLAGS ===============================
# =====================================================

while getopts "b:m:c:z:r:f:p:t:" opt; do
  case $opt in
    b) BBOX="$OPTARG" ;;
    m) REF_DATE="$OPTARG" ;;
    c) C="$OPTARG" ;;
    z) Z="$OPTARG" ;;
    r) R="$OPTARG" ;;
    f) F="$OPTARG" ;;
    p) NUM_PROC="$OPTARG" ;;
    t) OMP_THREADS="$OPTARG" ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
done

# =====================================================
# === THREAD SETTINGS =================================
# =====================================================

export OMP_NUM_THREADS=${OMP_THREADS}
export OPENBLAS_NUM_THREADS=${OMP_THREADS}
export MKL_NUM_THREADS=${OMP_THREADS}

echo "Using NUM_PROC=${NUM_PROC}"
echo "Using OMP_NUM_THREADS=${OMP_THREADS}"

# =====================================================
# === WORKDIR =========================================
# =====================================================

DATA_NAME=$(basename "$DATA_DIR")
WORKDIR="/data/stack_${DATA_NAME}_c${C}_z${Z}_r${R}_f${F}"

echo "=== WORKDIR: $WORKDIR ==="

START_TOTAL=$(date +%s)

# safety check
if [[ "$WORKDIR" == "/data" || -z "$WORKDIR" ]]; then
    echo "ERROR: WORKDIR is unsafe!"
    exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/logs"
mkdir -p "$AUX_DIR"

# =====================================================
# === RUN stackSentinel.py =============================
# =====================================================

echo "=== Running stackSentinel.py ==="

START_SS=$(date +%s)

stackSentinel.py \
  -s "$DATA_DIR" \
  -o "$ORB_DIR" \
  -a "$AUX_DIR" \
  -d "$DEM" \
  -w "$WORKDIR" \
  -b "$BBOX" \
  -m "$REF_DATE" \
  -c "$C" \
  -z "$Z" \
  -r "$R" \
  -f "$F" \
  --num_proc "$NUM_PROC" \
  2>&1 | tee "$WORKDIR/logs/stackSentinel.log"

END_SS=$(date +%s)
SS_TIME=$((END_SS - START_SS))

printf "stackSentinel.py took %02d:%02d (mm:ss)\n" $((SS_TIME/60)) $((SS_TIME%60)) \
    | tee -a "$WORKDIR/timing.log"

# =====================================================
# === RUN ALL STEPS ===================================
# =====================================================

echo "=== Running ISCE steps ==="

cd "$WORKDIR/run_files"

ln -sf "$DEM" .
ln -sf "${DEM}.vrt" .
ln -sf "${DEM}.xml" . 2>/dev/null || true

for runfile in run_*; do
    [ -e "$runfile" ] || continue
    echo ">>> Running $runfile"

    START_STEP=$(date +%s)

    OMP_NUM_THREADS="$OMP_THREADS" \
    OPENBLAS_NUM_THREADS="$OMP_THREADS" \
    MKL_NUM_THREADS="$OMP_THREADS" \
    bash "$runfile" 2>&1 | tee "$WORKDIR/logs/${runfile}.log"

    END_STEP=$(date +%s)
    DURATION=$((END_STEP - START_STEP))

    printf ">>> %s took %02d:%02d (mm:ss)\n" "$runfile" $((DURATION/60)) $((DURATION%60)) \
        | tee -a "$WORKDIR/timing.log"
done

END_TOTAL=$(date +%s)
TOTAL_TIME=$((END_TOTAL - START_TOTAL))

echo "=== TOTAL PROCESSING TIME ===" | tee -a "$WORKDIR/timing.log"
printf "TOTAL: %02d:%02d (mm:ss)\n" $((TOTAL_TIME/60)) $((TOTAL_TIME%60)) \
    | tee -a "$WORKDIR/timing.log"

echo "=== DONE ==="