#!/bin/bash

# ===============================================
# Download observations for WRF DA
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

# Load the environment setup script
source /home/wrf/WRF_Model/scripts/env.sh

# Input variables
YYYY=$1  # Year
MM=$2    # Month
DD=$3    # Day
HH=$4    # Hour

# Base URL
BASE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/gdas.${YYYY}${MM}${DD}/"

# Files to download
FILES=(
    "gdas.t${HH}z.1bamua.tm00.bufr_d"
    "gdas.t${HH}z.1bhrs4.tm00.bufr_d"
    "gdas.t${HH}z.1bmhs.tm00.bufr_d"
    "gdas.t${HH}z.airsev.tm00.bufr_d"
    "gdas.t${HH}z.atms.tm00.bufr_d"
    "gdas.t${HH}z.mtiasi.tm00.bufr_d"
    "gdas.t${HH}z.gpsro.tm00.bufr_d.nr"
    "gdas.t${HH}z.prepbufr.nr"
)

# Download the files
mkdir -p $BASE_DIR/DA_input/ob
cd $BASE_DIR/DA_input/ob
for FILE in "${FILES[@]}"; do
    URL="${BASE_URL}${FILE}"
    echo "Downloading ${FILE}..."
    curl -O "${URL}"
done

mv gdas.t${HH}z.1bamua.tm00.bufr_d amsua.bufr
mv gdas.t${HH}z.1bhrs4.tm00.bufr_d hirs4.bufr
mv gdas.t${HH}z.1bmhs.tm00.bufr_d mhs.bufr
mv gdas.t${HH}z.airsev.tm00.bufr_d airs.bufr
mv gdas.t${HH}z.atms.tm00.bufr_d atms.bufr
mv gdas.t${HH}z.mtiasi.tm00.bufr_d iasi.bufr
mv gdas.t${HH}z.gpsro.tm00.bufr_d.nr gpsro.bufr
mv gdas.t${HH}z.prepbufr.nr ob.bufr

echo "Download complete!"