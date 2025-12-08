#!/bin/bash
# ===============================================
# Setup and configure WRFDA gen_be_wrapper.ksh for background error matrix creation
# Modifies the existing gen_be_wrapper.ksh with domain-specific settings
# Author: Mikael Hasu
# Date: December 2025
# ===============================================

source $(dirname $0)/env_test.sh

echo "Setting up GEN_BE wrapper configuration..."

# Check if WRFDA is installed
if [ ! -f "${BASE_DIR}/WRFDA/var/scripts/gen_be/gen_be_wrapper.ksh" ]; then
    echo "ERROR: gen_be_wrapper.ksh not found at ${BASE_DIR}/WRFDA/var/scripts/gen_be/"
    echo "Please ensure WRFDA is properly installed."
    exit 1
fi

# Check if we have sufficient data
FC_COUNT=$(find ${GENBE_FC_DIR} -type d -name "20*" 2>/dev/null | wc -l)
echo "Found $FC_COUNT forecast initialization times"

if [ $FC_COUNT -lt 30 ]; then
    echo "WARNING: Only $FC_COUNT forecast times found."
    echo "For reliable BE statistics, at least 30 days (60 forecast times at 00Z and 12Z) is recommended."
    echo "Continue anyway? (y/n)"
    read answer
    if [ "$answer" != "y" ]; then
        exit 1
    fi
fi

# Get the first and last dates from available forecasts
START_DATE=$(find ${GENBE_FC_DIR} -type d -name "20*" | sort | head -1 | xargs basename)
END_DATE=$(find ${GENBE_FC_DIR} -type d -name "20*" | sort | tail -1 | xargs basename)

if [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
    echo "ERROR: Could not determine START_DATE and END_DATE from forecast data."
    echo "Please check that forecast files exist in ${GENBE_FC_DIR}"
    exit 1
fi

echo "Forecast period: $START_DATE to $END_DATE"

# Determine NUM_LEVELS from a sample wrfout file
SAMPLE_FILE=$(find ${GENBE_FC_DIR} -name "wrfout_d01_*" | head -1)
if [ -f "$SAMPLE_FILE" ]; then
    # Extract e_vert from wrfout file and calculate NUM_LEVELS
    NUM_LEVELS_CALC=$(ncdump -h "$SAMPLE_FILE" 2>/dev/null | grep "bottom_top = " | awk '{print $3}')
    if [ -n "$NUM_LEVELS_CALC" ]; then
        export NUM_LEVELS=$NUM_LEVELS_CALC
        echo "Detected NUM_LEVELS from wrfout file: $NUM_LEVELS"
    else
        echo "WARNING: Could not auto-detect NUM_LEVELS. Using default from env_test.sh"
    fi
else
    echo "WARNING: No sample wrfout file found. Using NUM_LEVELS from env_test.sh"
fi

# Create GEN_BE run directory
GENBE_RUN_DIR="${GENBE_DIR}/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$GENBE_RUN_DIR"

echo "Creating run directory: $GENBE_RUN_DIR"

# Copy and modify the gen_be_wrapper script
cp ${BASE_DIR}/WRFDA/var/scripts/gen_be/gen_be_wrapper.ksh "$GENBE_RUN_DIR/"
cd "$GENBE_RUN_DIR"

# Modify gen_be_wrapper.ksh with correct settings
sed -i "s|^export WRFVAR_DIR=.*|export WRFVAR_DIR=${BASE_DIR}/WRFDA|" gen_be_wrapper.ksh
sed -i "s|^export NL_CV_OPTIONS=.*|export NL_CV_OPTIONS=${NL_CV_OPTIONS}|" gen_be_wrapper.ksh
sed -i "s|^export BIN_TYPE=.*|export BIN_TYPE=${BIN_TYPE}|" gen_be_wrapper.ksh
sed -i "s|^export START_DATE=.*|export START_DATE=${START_DATE}|" gen_be_wrapper.ksh
sed -i "s|^export END_DATE=.*|export END_DATE=${END_DATE}|" gen_be_wrapper.ksh
sed -i "s|^export NUM_LEVELS=.*|export NUM_LEVELS=${NUM_LEVELS}|" gen_be_wrapper.ksh
sed -i "s|^export BE_METHOD=.*|export BE_METHOD=NMC|" gen_be_wrapper.ksh
sed -i "s|^export FC_DIR=.*|export FC_DIR=${GENBE_FC_DIR}|" gen_be_wrapper.ksh
sed -i "s|^export RUN_DIR=.*|export RUN_DIR=${GENBE_RUN_DIR}/gen_be\${BIN_TYPE}_cv\${NL_CV_OPTIONS}|" gen_be_wrapper.ksh
sed -i "s|^export DOMAIN=.*|export DOMAIN=01|" gen_be_wrapper.ksh
sed -i "s|^export FCST_RANGE1=.*|export FCST_RANGE1=${GENBE_FCST_RANGE2}|" gen_be_wrapper.ksh
sed -i "s|^export FCST_RANGE2=.*|export FCST_RANGE2=${GENBE_FCST_RANGE1}|" gen_be_wrapper.ksh
sed -i "s|^export INTERVAL=.*|export INTERVAL=12|" gen_be_wrapper.ksh
sed -i "s|^export STRIDE=.*|export STRIDE=1|" gen_be_wrapper.ksh
sed -i "s|^export USE_RFi=.*|export USE_RFi=true|" gen_be_wrapper.ksh

# Make the script executable
chmod +x gen_be_wrapper.ksh

echo ""
echo "✅ GEN_BE wrapper configured successfully!"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Configuration Summary:"
echo "─────────────────────────────────────────────────────────────"
echo "  Run Directory:     $GENBE_RUN_DIR"
echo "  Start Date:        $START_DATE"
echo "  End Date:          $END_DATE"
echo "  Forecast Times:    $FC_COUNT"
echo "  Vertical Levels:   $NUM_LEVELS"
echo "  CV Option:         $NL_CV_OPTIONS"
echo "  Bin Type:          $BIN_TYPE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "To run GEN_BE:"
echo "  cd $GENBE_RUN_DIR"
echo "  ./gen_be_wrapper.ksh"
echo ""
echo "Output BE file will be in:"
echo "  ${GENBE_RUN_DIR}/gen_be${BIN_TYPE}_cv${NL_CV_OPTIONS}/be.dat"
echo ""
echo "See README.txt in the run directory for more details."
echo ""

exit 0
