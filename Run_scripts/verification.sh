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
# Step 1: Extract essential variables from WRF files and concatenate
##########################################################################
echo "Extracting essential variables from WRF output files..."

# Define the variables we need for verification
VERIF_VARS="T2,RAINC,RAINNC,RAINSH,HGT,LANDMASK,U10,V10,PSFC,Q2,Times"

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
ncrcat ${TEMP_DIR}/wrfout_verif_d01_* ${FORECAST_DIR}/wrf_d01

echo "Concatenating filtered domain 2 files..."
ncrcat ${TEMP_DIR}/wrfout_verif_d02_* ${FORECAST_DIR}/wrf_d02

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

# Process domain 1 forecasts
Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d01

# Process domain 2 forecasts
Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d02

##########################################################################
# Step 4: Perform verification for different parameters (weekly schedule)
##########################################################################

# Get current day of week (0 is Sunday, 6 is Saturday)
DAY_OF_WEEK=$(date --utc +'%w' -d "${year}-${month}-${day}")

# Determine whether to run weekly verification
# Run only on Monday (1) at 00 UTC cycle
if [ "$DAY_OF_WEEK" = "1" ] && [ "$cycle" = "00" ]; then
    echo "Today is Monday at 00 UTC - performing weekly and monthly verification..."
    
    # Calculate dates for weekly and monthly verification
    SEVEN_DAYS_AGO=$(date --utc +'%Y%m%d%H' -d "${year}-${month}-${day} ${cycle}:00:00 - 7 day")
    THIRTY_DAYS_AGO=$(date --utc +'%Y%m%d%H' -d "${year}-${month}-${day} ${cycle}:00:00 - 30 day")
    
    # Run verification for various parameters with both weekly and monthly periods
    echo "Performing verification for meteorological parameters..."
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${SEVEN_DAYS_AGO} --end_date ${CURRENT_DATE} --domain d01  #weekly
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${SEVEN_DAYS_AGO} --end_date ${CURRENT_DATE} --domain d02  #weekly

    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${THIRTY_DAYS_AGO} --end_date ${CURRENT_DATE} --domain d01  #monthly
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${THIRTY_DAYS_AGO} --end_date ${CURRENT_DATE} --domain d02  #monthly

    mv $BASE_DIR/Verification/Results/wrf_d01/*rds ~/R/x86_64-redhat-linux-gnu-library/4.5/harpVis/verification/det/
    mv $BASE_DIR/Verification/Results/wrf_d02/*rds ~/R/x86_64-redhat-linux-gnu-library/4.5/harpVis/verification/det/

else
    echo "Not Monday at 00 UTC - skipping verification process"
fi

##########################################################################
# Step 5: Clean up temporary files
##########################################################################
echo "Cleaning up temporary files..."

rm -rf ${TEMP_DIR}/*

echo "Verification process completed successfully!"

