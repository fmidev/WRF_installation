#!/bin/bash

#########################################################################
######## WRF_test Verification Process #####
# Compares WRF_test and production WRF against observations
# Author: Mikael Hasu
# Date: November 2025
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

# Source test environment to get TEST_BASE_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source ${SCRIPT_DIR}/env_test.sh

# Define date
CURRENT_DATE="${year}${month}${day}${cycle}"

# Use production directories for verification infrastructure and observations
VERIFICATION_SCRIPTS="${BASE_DIR}/Verification/scripts"
DATA_DIR="${BASE_DIR}/Verification/Data"
SQLITE_DIR="${BASE_DIR}/Verification/SQlite_tables"
OBS_DIR="${DATA_DIR}/Obs"
FORECAST_DIR="${DATA_DIR}/Forecast"
TEMP_DIR="${DATA_DIR}/temp"

# Create directories if they don't exist
mkdir -p ${FORECAST_DIR}
mkdir -p ${SQLITE_DIR}/Obs
mkdir -p ${SQLITE_DIR}/FCtables
mkdir -p ${TEMP_DIR}

echo "==========================================================================="
echo "WRF_test Verification - Comparing test and production WRF outputs"
echo "Date: ${CURRENT_DATE}"
echo "==========================================================================="

##########################################################################
# Step 1: Extract essential variables from WRF_test files
##########################################################################
echo "Extracting essential variables from WRF_test output files..."

# Define the variables we need for verification
VERIF_VARS="T2,RAINC,RAINNC,HGT,U10,V10,PSFC,Q2,Times"

# Process WRF_test domain 1 files
echo "Processing WRF_test domain 1 files..."
if [ -d "${PROD_DIR}/${CURRENT_DATE}" ]; then
    for wrfout in ${PROD_DIR}/${CURRENT_DATE}/wrfout_d01_*; do
        if [ -f "$wrfout" ]; then
            timestamp=$(basename "$wrfout" | sed 's/wrfout_d01_//')
            echo "Extracting from $(basename "$wrfout")..."
            ncks -v ${VERIF_VARS} ${wrfout} ${TEMP_DIR}/wrfout_verif_test_d01_${timestamp}
        fi
    done
    
    # Concatenate the filtered files
    if ls ${TEMP_DIR}/wrfout_verif_test_d01_* 1> /dev/null 2>&1; then
        echo "Concatenating WRF_test domain 1 files..."
        ncrcat ${TEMP_DIR}/wrfout_verif_test_d01_* ${FORECAST_DIR}/wrf_test_d01_${CURRENT_DATE}
    fi
else
    echo "Warning: WRF_test output directory not found: ${PROD_DIR}/${CURRENT_DATE}"
fi

# Process WRF_test domain 2 files
echo "Processing WRF_test domain 2 files..."
if [ -d "${PROD_DIR}/${CURRENT_DATE}" ]; then
    for wrfout in ${PROD_DIR}/${CURRENT_DATE}/wrfout_d02_*; do
        if [ -f "$wrfout" ]; then
            timestamp=$(basename "$wrfout" | sed 's/wrfout_d02_//')
            echo "Extracting from $(basename "$wrfout")..."
            ncks -v ${VERIF_VARS} ${wrfout} ${TEMP_DIR}/wrfout_verif_test_d02_${timestamp}
        fi
    done
    
    # Concatenate the filtered files
    if ls ${TEMP_DIR}/wrfout_verif_test_d02_* 1> /dev/null 2>&1; then
        echo "Concatenating WRF_test domain 2 files..."
        ncrcat ${TEMP_DIR}/wrfout_verif_test_d02_* ${FORECAST_DIR}/wrf_test_d02_${CURRENT_DATE}
    fi
else
    echo "Warning: WRF_test output directory not found: ${PROD_DIR}/${CURRENT_DATE}"
fi

##########################################################################
# Step 2: Read forecast data and save to SQLite
##########################################################################
echo "Converting forecast data to SQLite format..."

# Process WRF_test forecasts
echo "Processing WRF_test forecasts..."
cd ${VERIFICATION_SCRIPTS}

# Check if we have test forecast files before processing
if [ -f "${FORECAST_DIR}/wrf_test_d01_${CURRENT_DATE}" ]; then
    echo "Processing WRF_test domain 1..."
    Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d01 test
else
    echo "Warning: WRF_test domain 1 forecast file not found: ${FORECAST_DIR}/wrf_test_d01_${CURRENT_DATE}"
fi

if [ -f "${FORECAST_DIR}/wrf_test_d02_${CURRENT_DATE}" ]; then
    echo "Processing WRF_test domain 2..."
    Rscript ${VERIFICATION_SCRIPTS}/read_forecast_wrf.R ${CURRENT_DATE} d02 test
else
    echo "Warning: WRF_test domain 2 forecast file not found: ${FORECAST_DIR}/wrf_test_d02_${CURRENT_DATE}"
fi


##########################################################################
# Step 3: Perform verification on Wednesday at 12 UTC
##########################################################################

# Get current day of week (0 is Sunday, 6 is Saturday)
DAY_OF_WEEK=$(date --utc +'%w' -d "${year}-${month}-${day}")

# Normalize numeric month/day (handles leading zeros) for arithmetic/comparisons
month_num=$((10#${month}))
day_num=$((10#${day}))

# Determine whether to run weekly verification
# Run only on Wednesday (3) at 12 UTC cycle
if [ "$DAY_OF_WEEK" = "3" ] && [ "$cycle" = "12" ]; then
    echo "Today is Wednesday at 12 UTC - performing verification..."

    DATE_STRING="${year}-${month}-${day} 00:00:00"
    VERIF_START=$(date -u -d "$DATE_STRING UTC -2 days" +'%Y%m%d%H')
    SEVEN_DAYS_AGO=$(date -u -d "$DATE_STRING UTC -9 days" +'%Y%m%d%H')
    THIRTY_DAYS_AGO=$(date -u -d "$DATE_STRING UTC -32 days" +'%Y%m%d%H')

    echo "CURRENT_DATE: $CURRENT_DATE"
    echo "VERIF_START: $VERIF_START"
    echo "SEVEN_DAYS_AGO: $SEVEN_DAYS_AGO"
    echo "THIRTY_DAYS_AGO: $THIRTY_DAYS_AGO"
    
    # Run verification for various parameters with both weekly and monthly periods
    echo "Performing verification for meteorological parameters..."
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${SEVEN_DAYS_AGO} --end_date ${VERIF_START} --subdir weekly -m "wrf_d01,wrf_d02,wrf_test_d01,wrf_test_d02" -n "" -f "12h"
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${THIRTY_DAYS_AGO} --end_date ${VERIF_START} --subdir past_30_days -m "wrf_d01,wrf_d02,wrf_test_d01,wrf_test_d02" -n "" -f "12h"

    # Seasonal verification: run on the first Wednesday (day 1-7) at 12 UTC when a new season starts
    # New season months: March(3)->MAM, June(6)->JJA, September(9)->SON, December(12)->DJF
    if { [ ${month_num} -eq 3 ] || [ ${month_num} -eq 6 ] || [ ${month_num} -eq 9 ] || [ ${month_num} -eq 12 ]; } && [ ${day_num} -le 7 ]; then
        echo "First Wednesday of season-start month detected (month=${month_num}, day=${day_num}) - performing seasonal verification for last season..."

        # Determine last season start/end (YYYY MM) depending on the new season month
        case "${month_num}" in
            3)
                # New season MAM -> last season DJF (Dec prev year - Feb current year)
                s_start_year=$((year-1)); s_start_month=12
                s_end_year=${year}; s_end_month=2
                season_name="DJF"
                ;;
            6)
                # New season JJA -> last season MAM (Mar - May)
                s_start_year=${year}; s_start_month=3
                s_end_year=${year}; s_end_month=5
                season_name="MAM"
                ;;
            9)
                # New season SON -> last season JJA (Jun - Aug)
                s_start_year=${year}; s_start_month=6
                s_end_year=${year}; s_end_month=8
                season_name="JJA"
                ;;
            12)
                # New season DJF -> last season SON (Sep - Nov)
                s_start_year=${year}; s_start_month=9
                s_end_year=${year}; s_end_month=11
                season_name="SON"
                ;;
        esac

        # Format months to two digits
        s_start_month=$(printf "%02d" ${s_start_month})
        s_end_month=$(printf "%02d" ${s_end_month})

        # Season start: first day of start month at 00 UTC
        season_start="${s_start_year}${s_start_month}0100"

        # Season end: last day of end month at 23 UTC
        last_day=$(date -u -d "${s_end_year}-${s_end_month}-01 +1 month -1 day" +'%d')
        last_day=$(printf "%02d" ${last_day})
        season_end="${s_end_year}${s_end_month}${last_day}23"

        echo "Season: ${season_name}, start: ${season_start}, end: ${season_end}"
        Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${season_start} --end_date ${season_end} --subdir seasonal -m "wrf_d01,wrf_d02,wrf_test_d01,wrf_test_d02" -n "" -f "12h"
    fi

else
    echo "Not Wednesday at 12 UTC - skipping verification process"
fi


##########################################################################
# Step 5: Clean up
##########################################################################
echo "Cleaning up temporary files..."

rm -rf ${TEMP_DIR}/*
rm -f ${FORECAST_DIR}/wrf_test*

echo "WRF_test verification process completed successfully!"
