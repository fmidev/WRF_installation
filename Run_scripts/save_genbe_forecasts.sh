#!/bin/bash
# ===============================================
# Save WRF forecasts for GEN_BE B matrix creation
# Organizes forecasts in the format required by gen_be_wrapper
# Author: Mikael Hasu
# Date: December 2025
# ===============================================

source $(dirname $0)/env_test.sh

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 YYYY MM DD HH"
    exit 1
fi

YYYY=$1
MM=$2
DD=$3
HH=$4

INIT_TIME="${YYYY}${MM}${DD}${HH}"
WRF_RUN_DIR="${PROD_DIR}/${YYYY}${MM}${DD}_${HH}"

# Check if WRF run directory exists
if [ ! -d "$WRF_RUN_DIR" ]; then
    echo "ERROR: WRF run directory not found: $WRF_RUN_DIR"
    exit 1
fi

# Only save if SAVE_GENBE_FORECASTS is enabled
if [ "$SAVE_GENBE_FORECASTS" != "true" ]; then
    echo "SAVE_GENBE_FORECASTS is not enabled. Skipping..."
    exit 0
fi

echo "Saving GEN_BE forecasts for initialization time: $INIT_TIME"

# Calculate valid times for 12h and 24h forecasts
VALID_12H=$(date -u -d "${YYYY}-${MM}-${DD} ${HH}:00:00 +12 hours" +"%Y-%m-%d_%H:%M:%S")
VALID_24H=$(date -u -d "${YYYY}-${MM}-${DD} ${HH}:00:00 +24 hours" +"%Y-%m-%d_%H:%M:%S")

# Create directory structure: YYYYMMDDHH/wrfout_d01_YYYY-MM-DD_HH:MM:SS
GENBE_INIT_DIR="${GENBE_FC_DIR}/${INIT_TIME}"
mkdir -p "$GENBE_INIT_DIR"

# Copy 12-hour and 24-hour forecast files for d01 only
# 12-hour forecast
if [ -f "${WRF_RUN_DIR}/wrfout_d01_${VALID_12H}" ]; then
    cp "${WRF_RUN_DIR}/wrfout_d01_${VALID_12H}" "${GENBE_INIT_DIR}/"
    echo "Saved 12h forecast: wrfout_d01_${VALID_12H}"
else
    echo "WARNING: 12h forecast file not found: wrfout_d01_${VALID_12H}"
fi

# 24-hour forecast
if [ -f "${WRF_RUN_DIR}/wrfout_d01_${VALID_24H}" ]; then
    cp "${WRF_RUN_DIR}/wrfout_d01_${VALID_24H}" "${GENBE_INIT_DIR}/"
    echo "Saved 24h forecast: wrfout_d01_${VALID_24H}"
else
    echo "WARNING: 24h forecast file not found: wrfout_d01_${VALID_24H}"
fi

echo "GEN_BE forecast files saved to: $GENBE_INIT_DIR"
echo "After collecting sufficient data (at least 1 month), run setup_genbe_wrapper.sh"

exit 0
