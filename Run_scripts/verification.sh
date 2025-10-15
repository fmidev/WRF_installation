#!/bin/bash

#########################################################################
######## Complete WRF Verification Process #####
#########################################################################

# Check if arguments are provided
if [ $# -lt 4 ]; then
    echo "Usage: $0 <year> <month> <day> <cycle>"
    exit 1
fi

year=$1
month=$2
day=$3
cycle=$4

source /home/wrf/WRF_Model/scripts/env.sh

# Define paths based on env.sh variables
VERIFICATION_SCRIPTS="${BASE_DIR}/Verification/scripts"
DATA_DIR="${BASE_DIR}/Verification/Data"
SQLITE_DIR="${BASE_DIR}/Verification/SQlite_tables"
FORECAST_DIR="${DATA_DIR}/Forecast"
OBS_DIR="${DATA_DIR}/Obs"
FIGURES_DIR="${DATA_DIR}/Figures"
TEMP_DIR="${DATA_DIR}/temp"
GFS_DIR="${BASE_DIR}/WRF_Model/GFS/${CURRENT_DATE}"

# Create directories if they don't exist
mkdir -p ${FORECAST_DIR}
mkdir -p ${OBS_DIR}
mkdir -p ${SQLITE_DIR}/Obs
mkdir -p ${SQLITE_DIR}/FCtables
mkdir -p ${FIGURES_DIR}
mkdir -p ${TEMP_DIR}

# Define date
CURRENT_DATE="${year}${month}${day}${cycle}"

##########################################################################
# Step 1a: Extract essential variables from WRF files and concatenate
##########################################################################
echo "Extracting essential variables from WRF output files..."

# Define the variables we need for verification
VERIF_VARS="T2,RAINC,RAINNC,HGT,U10,V10,PSFC,Q2,Times"

# Process domain 1 files
echo "Processing domain 1 files..."
for wrfout in ${PROD_DIR}/${CURRENT_DATE}/wrfout_d01_*; do
    # Extract the timestamp from the filename
    timestamp=$(basename "$wrfout" | sed 's/wrfout_d01_//')
    # Extract only the variables needed for verification
    echo "Extracting essential variables from $(basename "$wrfout")..."
    ncks -v ${VERIF_VARS} ${wrfout} ${TEMP_DIR}/wrfout_verif_d01_${timestamp}
done

# Process domain 2 files
echo "Processing domain 2 files..."
for wrfout in ${PROD_DIR}/${CURRENT_DATE}/wrfout_d02_*; do
    # Extract the timestamp from the filename
    timestamp=$(basename "$wrfout" | sed 's/wrfout_d02_//')
    # Extract only the variables needed for verification
    echo "Extracting essential variables from $(basename "$wrfout")..."
    ncks -v ${VERIF_VARS} ${wrfout} ${TEMP_DIR}/wrfout_verif_d02_${timestamp}
done

# Concatenate the filtered files
echo "Concatenating filtered domain 1 files..."
ncrcat ${TEMP_DIR}/wrfout_verif_d01_* ${FORECAST_DIR}/wrf_d01_${CURRENT_DATE}

echo "Concatenating filtered domain 2 files..."
ncrcat ${TEMP_DIR}/wrfout_verif_d02_* ${FORECAST_DIR}/wrf_d02_${CURRENT_DATE}

##########################################################################
# Step 1b: Process and concatenate GFS files
##########################################################################
echo "Processing GFS grib2 files..."

# Define the variables we need from GFS
GFS_VARS="2t|pres|orog|10u|10v|prate|2sh"

# Process each GFS file
for gfs_file in ${GFS_DIR}/gfs.t${cycle}z.pgrb2.0p25.f*; do
    if [ -f "$gfs_file" ]; then
        # Extract the forecast hour from filename
        f_hour=$(basename "$gfs_file" | sed 's/.*\.f\([0-9]*\)$/\1/')
        
        # Skip if forecast hour exceeds LEADTIME
        if [ "${f_hour}" -gt "${LEADTIME}" ]; then
            continue
        fi
        
        output_file="${TEMP_DIR}/gfs_processed_${f_hour}"
        
        echo "Processing GFS file for forecast hour ${f_hour}..."
        
        # Extract required variables using wgrib2
        wgrib2 "$gfs_file" -s | grep -E "${GFS_VARS}" | wgrib2 -i "$gfs_file" -netcdf "$output_file"
        
        if [ $? -ne 0 ]; then
            echo "Error processing GFS file: $gfs_file"
            exit 1
        fi
    fi
done

# Concatenate processed GFS files
echo "Concatenating processed GFS files..."
ncrcat ${TEMP_DIR}/gfs_processed_* ${FORECAST_DIR}/gfs_${CURRENT_DATE}

##########################################################################
# Step 2: Process observations directly to SQLite
##########################################################################
echo "Converting observations to SQLite format..."

# Convert CSV observations to SQLite directly using R script
cd ${VERIFICATION_SCRIPTS}
echo "Running read_obs.R to convert observations..."
Rscript read_obs.R ${CURRENT_DATE}

##########################################################################
# Step 3: Read forecast data and save to SQLite
##########################################################################
echo "Converting forecast data to SQLite format..."

# Process WRF forecasts
echo "Processing WRF forecasts..."
# Process domain 1 forecasts
Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d01

# Process domain 2 forecasts
Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d02

# Process GFS forecasts
echo "Processing GFS forecasts..."
Rscript ${VERIFICATION_SCRIPTS}/read_forecast_gfs.R ${CURRENT_DATE}

##########################################################################
# Step 4: Perform verification for different parameters (weekly schedule)
##########################################################################

# Get current day of week (0 is Sunday, 6 is Saturday)
DAY_OF_WEEK=$(date --utc +'%w' -d "${year}-${month}-${day}")

# Determine whether to run weekly verification
# Run only on Monday (1) at 00 UTC cycle
if [ "$DAY_OF_WEEK" = "1" ] && [ "$cycle" = "00" ]; then
    echo "Today is Monday at 00 UTC - performing weekly and monthly verification..."

    DATE_STRING="${year}-${month}-${day} ${cycle}:00:00"
    SEVEN_DAYS_AGO=$(date -u -d "$DATE_STRING UTC -7 days" +'%Y%m%d%H')
    THIRTY_DAYS_AGO=$(date -u -d "$DATE_STRING UTC -30 days" +'%Y%m%d%H')

    echo "CURRENT_DATE: $CURRENT_DATE"
    echo "SEVEN_DAYS_AGO: $SEVEN_DAYS_AGO"
    echo "THIRTY_DAYS_AGO: $THIRTY_DAYS_AGO"
    
    # Run verification for various parameters with both weekly and monthly periods
    echo "Performing verification for meteorological parameters..."
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${SEVEN_DAYS_AGO} --end_date ${CURRENT_DATE} #weekly
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${THIRTY_DAYS_AGO} --end_date ${CURRENT_DATE} #monthly

    cp $BASE_DIR/Verification/Results/*rds ~/R/library/harpVis/verification/det/

else
    echo "Not Monday at 00 UTC - skipping verification process"
fi

##########################################################################
# Step 5: Clean up temporary files
##########################################################################
echo "Cleaning up temporary files..."

rm -rf ${TEMP_DIR}/*

echo "Verification process completed successfully!"

