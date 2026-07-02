#!/bin/bash
set -euo pipefail

echo "=== stackSentinel entrypoint ==="

# =========================
# === REQUIRED PARAMS =====
# =========================

: "${OUTPUT_DIR:?OUTPUT_DIR is required}"

# optional but usually needed
: "${AUX_DIR:=${OUTPUT_DIR}/aux}"

# =========================
# === OPTIONAL PARAMS =====
# =========================

# reference data
: "${REF_DATE:=}"

# empty = no AOI cropping
: "${BBOX:=}"

# empty = use all swaths
: "${SWATHS:=}"

# empty = fresh run
# set = resume mode
: "${START_RUN:=}"

# empty = run until end
: "${END_RUN:=999}"

# coregistration
: "${COREGISTRATION:=}"

# snr misreg threshold
: "${SNR_MISREG_THRESHOLD:=}"

# esd coherence threshold
: "${ESD_COHERENCE_THRESHOLD:=}"

# number overlapping connections
: "${NUM_OVERLAP_CONNECTIONS:=}"

# interferogram formation
# number of connections
: "${C:=2}"

# multilooking azimuth
: "${Z:=2}"

# multilooking range
: "${R:=6}"

# goldstein filtering
: "${F:=0.5}"

# processing
: "${NUM_PROC:=}"
: "${NUM_PROC4TOPO:=}"
: "${OMP_THREADS:=}"


# virtual merge
: "${VIRTUAL_MERGE:=True}"

# for dry run
: "${DRY_RUN:=false}"

# =========================
# === MODE DETECTION ======
# =========================

if [[ -z "$START_RUN" ]]; then

    RESUME_MODE=false
    START_RUN=1

    echo "================================="
    echo "MODE: FRESH RUN"
    echo "================================="

else

    RESUME_MODE=true

    echo "================================="
    echo "MODE: RESUME RUN"
    echo "START_RUN=$START_RUN"
    echo "END_RUN=$END_RUN"
    echo "================================="

fi

# =====================================================
# === REQUIRED PARAMS DEPENDING ON MODE ===============
# =====================================================

if [[ "$RESUME_MODE" == false ]]; then

    : "${DATA_DIR:?DATA_DIR is required}"
    : "${ORB_DIR:?ORB_DIR is required}"
    : "${DEM:?DEM is required}"

fi

# =========================
# === THREAD CONTROL ======
# =========================

[[ -n "$OMP_THREADS" ]] && export OMP_NUM_THREADS="$OMP_THREADS"
[[ -n "$OMP_THREADS" ]] && export OPENBLAS_NUM_THREADS="$OMP_THREADS"
[[ -n "$OMP_THREADS" ]] && export MKL_NUM_THREADS="$OMP_THREADS"

# =========================
# === PARAMETER LOG =======
# =========================

write_parameter_log() {

    PARAM_LOG="$WORKDIR/parameters.log"

    echo "=== Writing parameter log to $PARAM_LOG ==="

    {
        echo ""
        echo "=================================================="
        echo "===== STACK SENTINEL PARAMETERS =================="
        echo "=================================================="

        echo "RUN_ID=$(date +%Y%m%d_%H%M%S)"
        echo "DATE=$(date)"
        echo ""

        echo "---- EXECUTION MODE ----"
        echo "RESUME_MODE=$RESUME_MODE"
        echo "START_RUN=$START_RUN"
        echo "END_RUN=$END_RUN"
        echo ""

        echo "---- PATHS ----"
        echo "OUTPUT_DIR=$OUTPUT_DIR"
        echo "DATA_DIR=${DATA_DIR:-<not set>}"
        echo "ORB_DIR=${ORB_DIR:-<not set>}"
        echo "DEM=${DEM:-<not set>}"
        echo "AUX_DIR=$AUX_DIR"
        echo ""

        echo "---- AOI ----"
        echo "BBOX=$BBOX"
        echo "SWATHS=$SWATHS"
        echo ""

        echo "---- TIME ----"
        echo "REF_DATE=${REF_DATE:-<not set>}"
        echo "RANGE_TAG=${RANGE_TAG:-<not set>}"
        echo ""

        echo "---- INPUT DATA ----"

        if [[ -f "$WORKDIR/input_scenes.txt" ]]; then
            echo "INPUT_SCENES_FILE=$WORKDIR/input_scenes.txt"
            echo "NUM_SCENES=$(wc -l < "$WORKDIR/input_scenes.txt")"
        else
            echo "INPUT_SCENES_FILE=<missing>"
            echo "NUM_SCENES=<unknown>"
        fi

        echo ""

        echo "---- PROCESSING PARAMS ----"

        echo "REF_DATE=$REF_DATE"

        echo "COREGISTRATION=${COREGISTRATION:-<default>}"
        echo "SNR_MISREG_THRESHOLD=${SNR_MISREG_THRESHOLD:-<default>}"
        echo "ESD_COHERENCE_THRESHOLD=${ESD_COHERENCE_THRESHOLD:-<default>}"
        echo "NUM_OVERLAP_CONNECTIONS=${NUM_OVERLAP_CONNECTIONS:-<default>}"

        echo "C=$C"
        echo "Z=$Z"
        echo "R=$R"
        echo "F=$F"

        echo "VIRTUAL_MERGE=$VIRTUAL_MERGE"

        echo ""

        echo "---- PARALLELIZATION ----"
        echo "NUM_PROC=${NUM_PROC:-<default>}"
        echo "NUM_PROC4TOPO=${NUM_PROC4TOPO:-<default>}"
        echo "OMP_THREADS=${OMP_THREADS:-<default>}"
        echo "OMP_NUM_THREADS=${OMP_NUM_THREADS:-<unset>}"
        echo "OPENBLAS_NUM_THREADS=${OPENBLAS_NUM_THREADS:-<unset>}"
        echo "MKL_NUM_THREADS=${MKL_NUM_THREADS:-<unset>}"
        echo ""

        echo "---- DERIVED ----"
        echo "WORKDIR=$WORKDIR"
        echo "ORIG_DATA_NAME=${ORIG_DATA_NAME:-<not set>}"
        echo ""

        echo "---- CONTAINER RESOURCES ----"
        echo "NPROC=$(nproc)"
        grep MemTotal /proc/meminfo || true
        echo ""

        echo "---- SOFTWARE ----"
        echo "stackSentinel.py=$(which stackSentinel.py)"
        snaphu -v 2>/dev/null | head -n1 || true
        gdalinfo --version 2>/dev/null || true
        echo ""

        echo "---- SYSTEM ----"
        echo "HOSTNAME=$(hostname)"
        echo ""

        echo "---- MEMORY ----"
        free -h || true
        echo ""

        echo "---- DISK ----"
        df -h "$OUTPUT_DIR" || true
        echo ""

        echo "=================================================="
        echo ""

    } | tee -a "$PARAM_LOG"
}

# =========================
# === DEBUG INPUT =========
# =========================

echo "========== DEBUG INPUT =========="
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "DATA_DIR=${DATA_DIR:-<not set>}"
echo "ORB_DIR=${ORB_DIR:-<not set>}"
echo "DEM=${DEM:-<not set>}"
echo "AUX_DIR=$AUX_DIR"
echo "BBOX=$BBOX"
echo "SWATHS=$SWATHS"
echo "START_RUN=$START_RUN"
echo "END_RUN=$END_RUN"
echo "================================="

# =====================================================
# === FRESH RUN: SAFE DETECTION + DATE EXTRACTION =====
# =====================================================

if [[ "$RESUME_MODE" == false ]]; then
    
    if [[ ! -d "$DATA_DIR" ]]; then
        echo "ERROR: DATA_DIR does not exist"
        exit 1
    fi

    shopt -s nullglob

    SAFE_FILES=("$DATA_DIR"/*.SAFE)

    if [[ ${#SAFE_FILES[@]} -eq 0 ]]; then

        echo "No SAFE files found directly in DATA_DIR"
        echo "Trying one level deeper..."

        SUBDIRS=("$DATA_DIR"/*/)

        for d in "${SUBDIRS[@]}"; do

            inner=("$d"/*.SAFE)

            if [[ ${#inner[@]} -gt 0 ]]; then
                DATA_DIR="$d"
                SAFE_FILES=("${inner[@]}")
                break
            fi
        done
    fi

    if [[ ${#SAFE_FILES[@]} -eq 0 ]]; then
        echo "ERROR: no SAFE files found"
        exit 1
    fi

    echo "SAFE count=${#SAFE_FILES[@]}"
    echo "Using DATA_DIR=$DATA_DIR"

    ORIG_DATA_NAME=$(basename "$DATA_DIR")

    DATES=()

    for f in "${SAFE_FILES[@]}"; do

        fname=$(basename "$f")

        date=$(echo "$fname" | grep -oE '[0-9]{8}' | head -n1 || true)

        if [[ -n "$date" ]]; then
            DATES+=("$date")
        fi
    done

    IFS=$'\n' SORTED=($(sort <<<"${DATES[*]}"))
    unset IFS

    MIN_DATE="${SORTED[0]}"
    MAX_DATE="${SORTED[-1]}"

    RANGE_TAG="${MIN_DATE}_${MAX_DATE}"

    echo "Detected date range:"
    echo "$MIN_DATE -> $MAX_DATE"

else

    echo "================================="
    echo "Resume mode:"
    echo "Skipping SAFE detection"
    echo "Skipping date extraction"
    echo "================================="

fi

# =========================
# === WORKDIR ============
# =========================

if [[ "$RESUME_MODE" == false ]]; then

    WORKDIR="${OUTPUT_DIR}/stack_${ORIG_DATA_NAME}_${RANGE_TAG}_c${C}_z${Z}_r${R}_f${F}"

else

    WORKDIR=$(find "$OUTPUT_DIR" \
        -maxdepth 1 \
        -type d \
        -name "stack_*" \
        | head -n1)

    if [[ -z "$WORKDIR" ]]; then
        echo "ERROR: no stack directory found in $OUTPUT_DIR"
        exit 1
    fi

fi

echo "WORKDIR=$WORKDIR"

# =========================
# === FRESH VS RESUME =====
# =========================

if [[ "$RESUME_MODE" == false ]]; then

    echo "================================="
    echo "Fresh run:"
    echo "Recreating WORKDIR"
    echo "================================="

    rm -rf "$WORKDIR"

    mkdir -p "$WORKDIR"
    mkdir -p "$WORKDIR/logs"
    mkdir -p "$AUX_DIR"

    printf "%s\n" "${SAFE_FILES[@]}" | sort > "$WORKDIR/input_scenes.txt"

else

    echo "================================="
    echo "Resume mode:"
    echo "Keeping existing WORKDIR"
    echo "================================="

    if [[ ! -d "$WORKDIR" ]]; then
        echo "ERROR: WORKDIR does not exist"
        exit 1
    fi

    mkdir -p "$WORKDIR/logs"

fi

if [[ "$RESUME_MODE" == false ]]; then
    write_parameter_log
fi

# =========================
# === DRY RUN ============
# =========================

if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN enabled"
    exit 0
fi

START_TOTAL=$(date +%s)

# =====================================================
# === RUN stackSentinel.py =============================
# =====================================================

if [[ "$RESUME_MODE" == false ]]; then

    echo "================================="
    echo "Running stackSentinel.py"
    echo "================================="

    # reference date
    REFDATE_ARGS=()

    if [[ -n "$REF_DATE" ]]; then
        REFDATE_ARGS=(-m "$REF_DATE")
    fi

    # coregistration method
    COREG_ARGS=()

    if [[ -n "$COREGISTRATION" ]]; then
        COREG_ARGS=(-C "$COREGISTRATION")
    fi

    # SNR threshold
    SNR_ARGS=()

    if [[ -n "$SNR_MISREG_THRESHOLD" ]]; then
        SNR_ARGS=(--snr_misreg_threshold "$SNR_MISREG_THRESHOLD")
    fi

    # ESD coherence threshold
    ESD_ARGS=()

    if [[ -n "$ESD_COHERENCE_THRESHOLD" ]]; then
        ESD_ARGS=(-e "$ESD_COHERENCE_THRESHOLD")
    fi

    # overlap connections
    OVERLAP_ARGS=()

    if [[ -n "$NUM_OVERLAP_CONNECTIONS" ]]; then
        OVERLAP_ARGS=(-O "$NUM_OVERLAP_CONNECTIONS")
    fi


    # setting a bounding box
    BBOX_ARGS=()

    if [[ -n "$BBOX" ]]; then
        BBOX_ARGS=(-b "$BBOX")
    fi

    # setting a swath selection
    SWATH_ARGS=()

    if [[ -n "$SWATHS" ]]; then
        SWATH_ARGS=(--swath_num "$SWATHS")
    fi

    # setting the number of processors
    NUMPROC_ARGS=()

    if [[ -n "$NUM_PROC" ]]; then
        NUMPROC_ARGS=(--num_proc "$NUM_PROC")
    fi

    # setting the number of processors for topo
    NUM_PROC4TOPO_ARGS=()

    if [[ -n "$NUM_PROC4TOPO" ]]; then
        NUM_PROC4TOPO_ARGS=(--num_proc4topo "$NUM_PROC4TOPO")
    fi

    VIRTUAL_MERGE_ARGS=(-V "$VIRTUAL_MERGE")


    START_SS=$(date +%s)

    stackSentinel.py \
        -s "$DATA_DIR" \
        -o "$ORB_DIR" \
        -a "$AUX_DIR" \
        -d "$DEM" \
        -w "$WORKDIR" \
        "${BBOX_ARGS[@]}" \
        "${SWATH_ARGS[@]}" \
        "${REFDATE_ARGS[@]}" \
        "${COREG_ARGS[@]}" \
        "${SNR_ARGS[@]}" \
        "${ESD_ARGS[@]}" \
        "${OVERLAP_ARGS[@]}" \
        -c "$C" \
        -z "$Z" \
        -r "$R" \
        -f "$F" \
        "${NUMPROC_ARGS[@]}" \
        "${NUM_PROC4TOPO_ARGS[@]}" \
        "${VIRTUAL_MERGE_ARGS[@]}" \
        2>&1 | tee "$WORKDIR/logs/stackSentinel.log"

    END_SS=$(date +%s)

    SS_TIME=$((END_SS - START_SS))

    printf "stackSentinel.py took %02d:%02d (mm:ss)\n" \
        $((SS_TIME/60)) \
        $((SS_TIME%60)) \
        | tee -a "$WORKDIR/timing.log"

else

    echo "================================="
    echo "Resume mode:"
    echo "Skipping stackSentinel.py"
    echo "================================="

fi

# =====================================================
# === RUNFILES ========================================
# =====================================================

RUN_DIR="$WORKDIR/run_files"

if [[ ! -d "$RUN_DIR" ]]; then
    echo "ERROR: run_files directory missing"
    exit 1
fi

cd "$RUN_DIR"

# DEM links only if DEM exists
if [[ -n "${DEM:-}" && -f "${DEM:-}" ]]; then

    ln -sf "$DEM" .

    [[ -f "${DEM}.vrt" ]] && ln -sf "${DEM}.vrt" .
    [[ -f "${DEM}.xml" ]] && ln -sf "${DEM}.xml" .

fi

# =====================================================
# === EXECUTE RUNFILES ================================
# =====================================================

for runfile in run_*; do

    [[ -f "$runfile" ]] || continue

    run_id=$(echo "$runfile" | sed -E 's/run_([0-9]+).*/\1/')
    run_id=$((10#$run_id))

    (( run_id < START_RUN )) && continue
    (( run_id > END_RUN )) && continue

    echo ""
    echo "================================="
    echo "RUNNING: $runfile"
    echo "RUN_ID:  $run_id"
    echo "================================="

    START_STEP=$(date +%s)

    bash "$runfile" \
        2>&1 | tee "$WORKDIR/logs/${runfile}.log"

    END_STEP=$(date +%s)

    DURATION=$((END_STEP - START_STEP))

    printf "%s took %02d:%02d (mm:ss)\n" \
        "$runfile" \
        $((DURATION/60)) \
        $((DURATION%60)) \
        | tee -a "$WORKDIR/timing.log"

done

# =====================================================
# === TOTAL TIME ======================================
# =====================================================

END_TOTAL=$(date +%s)

TOTAL_TIME=$((END_TOTAL - START_TOTAL))

echo ""
echo "================================="
echo "TOTAL PROCESSING TIME"
echo "================================="

printf "TOTAL: %02d:%02d (mm:ss)\n" \
    $((TOTAL_TIME/60)) \
    $((TOTAL_TIME%60)) \
    | tee -a "$WORKDIR/timing.log"

echo "=== DONE ==="