#!/bin/bash
set -euo pipefail

echo "=================================================="
echo "=== ISCE2 stackSentinel pipeline ================"
echo "=================================================="

# =====================================================
# === REQUIRED PARAMETER ==============================
# =====================================================

: "${OUTPUT_DIR:?OUTPUT_DIR is required}"

# OUTPUT_DIR is the ISCE2 working directory.
# No additional stack_* directory is created.

# =====================================================
# === OPTIONAL PARAMETERS =============================
# =====================================================

# Input data / auxiliary data
: "${DATA_DIR:=}"
: "${ORB_DIR:=}"
: "${DEM:=}"
: "${AUX_DIR:=${OUTPUT_DIR}/aux}"

# Workflow
: "${WORKFLOW:=interferogram}"

# stackSentinel preparation
: "${PREPARE_STACK:=false}"

# Runfile selection
: "${START_RUN:=1}"
: "${END_RUN:=999}"

# Reference data
: "${REF_DATE:=}"

# AOI
: "${BBOX:=}"
: "${SWATHS:=}"

# Coregistration
: "${COREGISTRATION:=}"

# SNR misregistration threshold
: "${SNR_MISREG_THRESHOLD:=}"

# ESD coherence threshold
: "${ESD_COHERENCE_THRESHOLD:=}"

# Number of overlapping connections
: "${NUM_OVERLAP_CONNECTIONS:=}"


# Interferogram formation
: "${C:=2}"
: "${Z:=2}"
: "${R:=6}"
: "${F:=0.5}"

# Processing
: "${NUM_PROC:=}"
: "${NUM_PROC4TOPO:=}"
: "${OMP_THREADS:=}"

# Virtual merge
: "${VIRTUAL_MERGE:=True}"

# Dry run
: "${DRY_RUN:=false}"


# =====================================================
# === VALIDATION ======================================
# =====================================================

if ! [[ "$START_RUN" =~ ^[0-9]+$ ]]; then
    echo "ERROR: START_RUN must be an integer"
    exit 1
fi

if ! [[ "$END_RUN" =~ ^[0-9]+$ ]]; then
    echo "ERROR: END_RUN must be an integer"
    exit 1
fi

if (( START_RUN > END_RUN )); then
    echo "ERROR: START_RUN ($START_RUN) is greater than END_RUN ($END_RUN)"
    exit 1
fi

if [[ "$PREPARE_STACK" != "true" && "$PREPARE_STACK" != "false" ]]; then
    echo "ERROR: PREPARE_STACK must be either true or false"
    exit 1
fi

# stackSentinel.py needs these parameters.
if [[ "$PREPARE_STACK" == "true" ]]; then

    : "${DATA_DIR:?DATA_DIR is required when PREPARE_STACK=true}"
    : "${ORB_DIR:?ORB_DIR is required when PREPARE_STACK=true}"
    : "${DEM:?DEM is required when PREPARE_STACK=true}"

fi


# =====================================================
# === DIRECTORIES =====================================
# =====================================================

# OUTPUT_DIR is the actual ISCE2 working directory.

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/logs"
mkdir -p "$AUX_DIR"

LOG_DIR="$OUTPUT_DIR/logs"
TIMING_LOG="$OUTPUT_DIR/timing.log"
PARAM_LOG="$OUTPUT_DIR/parameters.log"


# =====================================================
# === THREAD CONTROL ==================================
# =====================================================

if [[ -n "$OMP_THREADS" ]]; then
    export OMP_NUM_THREADS="$OMP_THREADS"
    export OPENBLAS_NUM_THREADS="$OMP_THREADS"
    export MKL_NUM_THREADS="$OMP_THREADS"
fi


# =====================================================
# === HELPER: FORMAT DURATION =========================
# =====================================================

format_duration() {

    local total_seconds="$1"

    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    printf "%02d:%02d:%02d" \
        "$hours" \
        "$minutes" \
        "$seconds"
}


# =====================================================
# === START TOTAL TIMER ===============================
# =====================================================

START_TOTAL=$(date +%s)


# =====================================================
# === LOG CONFIGURATION ===============================
# =====================================================

echo ""
echo "=================================================="
echo "CONFIGURATION"
echo "=================================================="

echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "PREPARE_STACK=$PREPARE_STACK"
echo "START_RUN=$START_RUN"
echo "END_RUN=$END_RUN"

echo ""
echo "---- INPUT DATA ----"
echo "DATA_DIR=${DATA_DIR:-<not set>}"
echo "ORB_DIR=${ORB_DIR:-<not set>}"
echo "DEM=${DEM:-<not set>}"
echo "AUX_DIR=$AUX_DIR"

echo "WORKFLOW=$WORKFLOW"

echo ""
echo "---- AOI ----"
echo "BBOX=${BBOX:-<not set>}"
echo "SWATHS=${SWATHS:-<not set>}"

echo ""
echo "---- PROCESSING ----"
echo "REF_DATE=${REF_DATE:-<not set>}"
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
echo "---- OUTPUT ----"
echo "ISCE2 WORKDIR=$OUTPUT_DIR"
echo "LOG_DIR=$LOG_DIR"
echo "TIMING_LOG=$TIMING_LOG"

echo ""
echo "---- SOFTWARE ----"
echo "stackSentinel.py=$(which stackSentinel.py)"
snaphu -v 2>/dev/null | head -n1 || true
gdalinfo --version 2>/dev/null || true

echo ""
echo "---- CONTAINER RESOURCES ----"
echo "NPROC=$(nproc)"
grep MemTotal /proc/meminfo || true

echo "=================================================="
echo ""


# =====================================================
# === WRITE PARAMETER FILE ============================
# =====================================================

if [[ "$PREPARE_STACK" == "true" ]]; then

    # =====================================================
    # === WRITE INPUT SCENES ==============================
    # =====================================================

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
        echo "ERROR: No SAFE files found in:"
        echo "$DATA_DIR"
        exit 1
    fi

    echo "Found ${#SAFE_FILES[@]} SAFE files"
    echo "Using DATA_DIR=$DATA_DIR"

    printf "%s\n" "${SAFE_FILES[@]}" | sort > "$OUTPUT_DIR/input_scenes.txt"

    echo "Input scenes written to:"
    echo "$OUTPUT_DIR/input_scenes.txt"

    {
        echo "=================================================="
        echo "ISCE2 PROCESSING PARAMETERS"
        echo "=================================================="
        echo "DATE=$(date)"
        echo ""

        echo "---- OUTPUT ----"
        echo "OUTPUT_DIR=$OUTPUT_DIR"
        echo ""

        echo "---- INPUT DATA ----"
        echo "DATA_DIR=$DATA_DIR"
        echo "ORB_DIR=$ORB_DIR"
        echo "DEM=$DEM"
        echo "AUX_DIR=$AUX_DIR"
        echo ""

        echo "---- AOI ----"
        echo "BBOX=$BBOX"
        echo "SWATHS=$SWATHS"
        echo ""

        echo "---- PROCESSING ----"
        echo "REF_DATE=$REF_DATE"
        echo "COREGISTRATION=$COREGISTRATION"
        echo "SNR_MISREG_THRESHOLD=$SNR_MISREG_THRESHOLD"
        echo "ESD_COHERENCE_THRESHOLD=$ESD_COHERENCE_THRESHOLD"
        echo "NUM_OVERLAP_CONNECTIONS=$NUM_OVERLAP_CONNECTIONS"
        echo "C=$C"
        echo "Z=$Z"
        echo "R=$R"
        echo "F=$F"
        echo "VIRTUAL_MERGE=$VIRTUAL_MERGE"
        echo ""

        echo "---- PARALLELIZATION ----"
        echo "NUM_PROC=$NUM_PROC"
        echo "NUM_PROC4TOPO=$NUM_PROC4TOPO"
        echo "OMP_THREADS=$OMP_THREADS"
        echo ""


        echo "---- SOFTWARE ----"
        echo "stackSentinel.py=$(which stackSentinel.py)"
        snaphu -v 2>/dev/null | head -n1 || true
        gdalinfo --version 2>/dev/null || true

        echo ""
        echo "=================================================="

    } > "$PARAM_LOG"

    echo "Parameter log written to:"
    echo "$PARAM_LOG"

fi


# =====================================================
# === DRY RUN =========================================
# =====================================================

if [[ "$DRY_RUN" == "true" ]]; then

    echo ""
    echo "DRY_RUN=true"
    echo "No processing will be executed."
    exit 0

fi


# =====================================================
# === PREPARE ISCE2 STACK =============================
# =====================================================

if [[ "$PREPARE_STACK" == "true" ]]; then

    echo ""
    echo "=================================================="
    echo "PREPARING ISCE2 STACK"
    echo "=================================================="
    echo "Working directory:"
    echo "$OUTPUT_DIR"
    echo ""

    # -----------------------------------------------
    # Reference date
    # -----------------------------------------------

    REFDATE_ARGS=()

    if [[ -n "$REF_DATE" ]]; then
        REFDATE_ARGS=(-m "$REF_DATE")
    fi


    # -----------------------------------------------
    # Coregistration method
    # -----------------------------------------------

    COREG_ARGS=()

    if [[ -n "$COREGISTRATION" ]]; then
        COREG_ARGS=(-C "$COREGISTRATION")
    fi


    # -----------------------------------------------
    # SNR threshold
    # -----------------------------------------------

    SNR_ARGS=()

    if [[ -n "$SNR_MISREG_THRESHOLD" ]]; then
        SNR_ARGS=(
            --snr_misreg_threshold
            "$SNR_MISREG_THRESHOLD"
        )
    fi


    # -----------------------------------------------
    # ESD coherence threshold
    # -----------------------------------------------

    ESD_ARGS=()

    if [[ -n "$ESD_COHERENCE_THRESHOLD" ]]; then
        ESD_ARGS=(
            -e
            "$ESD_COHERENCE_THRESHOLD"
        )
    fi


    # -----------------------------------------------
    # Overlap connections
    # -----------------------------------------------

    OVERLAP_ARGS=()

    if [[ -n "$NUM_OVERLAP_CONNECTIONS" ]]; then
        OVERLAP_ARGS=(
            -O
            "$NUM_OVERLAP_CONNECTIONS"
        )
    fi


    # -----------------------------------------------
    # Bounding box
    # -----------------------------------------------

    BBOX_ARGS=()

    if [[ -n "$BBOX" ]]; then
        BBOX_ARGS=(
            -b
            "$BBOX"
        )
    fi


    # -----------------------------------------------
    # Swath selection
    # -----------------------------------------------

    SWATH_ARGS=()

    if [[ -n "$SWATHS" ]]; then
        SWATH_ARGS=(
            --swath_num
            "$SWATHS"
        )
    fi


    # -----------------------------------------------
    # Number of processors
    # -----------------------------------------------

    NUMPROC_ARGS=()

    if [[ -n "$NUM_PROC" ]]; then
        NUMPROC_ARGS=(
            --num_proc
            "$NUM_PROC"
        )
    fi


    # -----------------------------------------------
    # Number of processors for topo
    # -----------------------------------------------

    NUM_PROC4TOPO_ARGS=()

    if [[ -n "$NUM_PROC4TOPO" ]]; then
        NUM_PROC4TOPO_ARGS=(
            --num_proc4topo
            "$NUM_PROC4TOPO"
        )
    fi


    # -----------------------------------------------
    # Virtual merge
    # -----------------------------------------------

    VIRTUAL_MERGE_ARGS=(
        -V
        "$VIRTUAL_MERGE"
    )


    # -----------------------------------------------
    # Run stackSentinel.py
    # -----------------------------------------------

    START_STACKSENTINEL=$(date +%s)

    echo "Running:"
    echo "stackSentinel.py"
    echo ""

    stackSentinel.py \
        -s "$DATA_DIR" \
        -o "$ORB_DIR" \
        -a "$AUX_DIR" \
        -d "$DEM" \
        -w "$OUTPUT_DIR" \
        -W "$WORKFLOW" \
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
        2>&1 | tee "$LOG_DIR/stackSentinel.log"


    END_STACKSENTINEL=$(date +%s)

    STACKSENTINEL_TIME=$((END_STACKSENTINEL - START_STACKSENTINEL))

    STACKSENTINEL_HMS=$(format_duration "$STACKSENTINEL_TIME")


    echo ""
    echo "stackSentinel.py completed."
    echo "Duration: $STACKSENTINEL_HMS"

    {
        echo "stackSentinel.py | $STACKSENTINEL_HMS"

    } | tee -a "$TIMING_LOG"

else

    echo ""
    echo "=================================================="
    echo "SKIPPING stackSentinel.py"
    echo "PREPARE_STACK=false"
    echo "=================================================="

fi


# =====================================================
# === RUNFILES ========================================
# =====================================================

RUN_DIR="$OUTPUT_DIR/run_files"

if [[ ! -d "$RUN_DIR" ]]; then

    echo ""
    echo "ERROR: run_files directory does not exist:"
    echo "$RUN_DIR"
    exit 1

fi


# =====================================================
# === DEM LINKS =======================================
# =====================================================

if [[ -n "${DEM:-}" && -f "${DEM:-}" ]]; then

    cd "$RUN_DIR"

    ln -sf "$DEM" .

    [[ -f "${DEM}.vrt" ]] && ln -sf "${DEM}.vrt" .
    [[ -f "${DEM}.xml" ]] && ln -sf "${DEM}.xml" .

fi


# =====================================================
# === FIND RUNFILES ===================================
# =====================================================

cd "$OUTPUT_DIR/run_files"

shopt -s nullglob

RUNFILES=(run_[0-9]*)

if [[ ${#RUNFILES[@]} -eq 0 ]]; then
    echo ""
    echo "ERROR: No runfiles found in:"
    echo "$OUTPUT_DIR/run_files"
    exit 1
fi

# Sort numerically by filename.
IFS=$'\n' RUNFILES=($(printf '%s\n' "${RUNFILES[@]}" | sort))
unset IFS

echo ""
echo "Found ${#RUNFILES[@]} runfiles:"
printf '  %s\n' "${RUNFILES[@]}"


# =====================================================
# === EXECUTE RUNFILES ================================
# =====================================================

echo ""
echo "=================================================="
echo "EXECUTING ISCE2 RUNFILES"
echo "=================================================="
echo "RUN_DIR=$RUN_DIR"
echo "START_RUN=$START_RUN"
echo "END_RUN=$END_RUN"
echo "=================================================="


RUN_COUNT=0
RUN_TOTAL_SECONDS=0

for runfile in "${RUNFILES[@]}"; do

    [[ -f "$runfile" ]] || continue

    if [[ "$runfile" =~ ^run_([0-9]+) ]]; then
        run_id="${BASH_REMATCH[1]}"
    else
        continue
    fi

    run_id=$((10#$run_id))

    (( run_id < START_RUN )) && continue
    (( run_id > END_RUN )) && continue

    RUN_COUNT=$((RUN_COUNT + 1))

    echo ""
    echo "=================================================="
    echo "RUNNING: $runfile"
    echo "=================================================="
    echo "Start time: $(date '+%Y-%m-%d %H:%M:%S')"

    START_RUNFILE=$(date +%s)

    bash "$runfile" \
        2>&1 | tee "$LOG_DIR/${runfile}.log"

    END_RUNFILE=$(date +%s)

    RUNFILE_TIME=$((END_RUNFILE - START_RUNFILE))
    RUN_TOTAL_SECONDS=$((RUN_TOTAL_SECONDS + RUNFILE_TIME))

    RUNFILE_HMS=$(format_duration "$RUNFILE_TIME")

    echo ""
    echo "--------------------------------------------------"
    echo "COMPLETED: $runfile"
    echo "Duration:  $RUNFILE_HMS"
    echo "End time:  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "--------------------------------------------------"

    echo "$runfile | $RUNFILE_HMS" | tee -a "$TIMING_LOG"

done


# =====================================================
# === TOTAL TIME ======================================
# =====================================================

END_TOTAL=$(date +%s)

TOTAL_TIME=$((END_TOTAL - START_TOTAL))
TOTAL_HMS=$(format_duration "$TOTAL_TIME")


# =====================================================
# === FINAL SUMMARY ===================================
# =====================================================

echo ""
echo ""
echo "=================================================="
echo "ISCE2 PROCESSING SUMMARY"
echo "=================================================="

if [[ "$PREPARE_STACK" == "true" ]]; then
    echo "stackSentinel.py: $STACKSENTINEL_HMS"
fi

echo "Runfiles executed: $RUN_COUNT"
echo "Runfile processing time: $(format_duration "$RUN_TOTAL_SECONDS")"
echo "TOTAL PROCESSING TIME: $TOTAL_HMS"

echo "=================================================="

{
    echo ""
    echo "=================================================="
    echo "FINAL SUMMARY"
    echo "=================================================="

    if [[ "$PREPARE_STACK" == "true" ]]; then
        echo "stackSentinel.py: $STACKSENTINEL_HMS"
    fi

    echo "Runfiles executed: $RUN_COUNT"
    echo "Runfile processing time: $(format_duration "$RUN_TOTAL_SECONDS")"
    echo "TOTAL PROCESSING TIME: $TOTAL_HMS"

    echo "=================================================="

} | tee -a "$TIMING_LOG"


# =====================================================
# === STORAGE SUMMARY =================================
# =====================================================

STORAGE_LOG="$OUTPUT_DIR/storage.log"

echo ""
echo "=================================================="
echo "ISCE2 STORAGE SUMMARY"
echo "=================================================="
echo "Output directory:"
echo "  $OUTPUT_DIR"
echo ""

# Total size of the complete ISCE2 working directory
TOTAL_STORAGE=$(du -sh "$OUTPUT_DIR" | awk '{print $1}')

echo "Total storage used:"
echo "  $TOTAL_STORAGE"
echo ""

echo "Storage by directory:"
echo "--------------------------------------------------"

du -sh "$OUTPUT_DIR"/*/ 2>/dev/null | sort -h

echo "--------------------------------------------------"

{
    echo "=================================================="
    echo "ISCE2 STORAGE SUMMARY"
    echo "=================================================="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "Output directory:"
    echo "  $OUTPUT_DIR"
    echo ""
    echo "Total storage used:"
    echo "  $TOTAL_STORAGE"
    echo ""
    echo "Storage by directory:"
    echo "--------------------------------------------------"
    du -sh "$OUTPUT_DIR"/*/ 2>/dev/null | sort -h
    echo "--------------------------------------------------"
    echo ""

} > "$STORAGE_LOG"

echo ""
echo "Storage log written to:"
echo "$STORAGE_LOG"

echo
echo "=== DONE ==="

