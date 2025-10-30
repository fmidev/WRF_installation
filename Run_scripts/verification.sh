#!/bin/bash

#########################################################################
######## WRF Verification Process #####
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

# Define date
CURRENT_DATE="${year}${month}${day}${cycle}"

# Define paths based on env.sh variables
VERIFICATION_SCRIPTS="${BASE_DIR}/Verification/scripts"
DATA_DIR="${BASE_DIR}/Verification/Data"
SQLITE_DIR="${BASE_DIR}/Verification/SQlite_tables"
FORECAST_DIR="${DATA_DIR}/Forecast"
OBS_DIR="${DATA_DIR}/Obs"
FIGURES_DIR="${DATA_DIR}/Figures"
TEMP_DIR="${DATA_DIR}/temp"
GFS_DIR="${BASE_DIR}/GFS/${CURRENT_DATE}"

# Create directories if they don't exist
mkdir -p ${FORECAST_DIR}
mkdir -p ${OBS_DIR}
mkdir -p ${SQLITE_DIR}/Obs
mkdir -p ${SQLITE_DIR}/FCtables
mkdir -p ${FIGURES_DIR}
mkdir -p ${TEMP_DIR}


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

GFS_VARS=':TMP:2 m above ground:|:PRES:surface:|:HGT:surface:|:UGRD:10 m above ground:|:VGRD:10 m above ground:|:SPFH:2 m above ground:|:PRATE:surface:'

echo "Extracting GFS variables..."
tp_cumulative="${TEMP_DIR}/gfs_tp_cumulative.grb2"

# Initialize cumulative precipitation file to zero
init_zero_base() {
    local sample_file=$1
    echo "Initializing zero cumulative precipitation..."
    wgrib2 "$sample_file" -match ":PRATE:surface:" \
        -set_var "APCP" -set_lev "surface" \
        -set_grib_type simple -set_ftime "0 hour fcst" \
        -grib_out "$tp_cumulative"
}

for gfs_file in ${GFS_DIR}/gfs.t${cycle}z.pgrb2.0p25.f*; do
    if [ ! -f "$gfs_file" ]; then
        echo "File not found: $gfs_file"
        continue
    fi

    f_hour=$(basename "$gfs_file" | sed 's/.*\.f\([0-9]*\)$/\1/')
    f_hour_num=$((10#${f_hour}))
    if [ "${f_hour_num}" -gt "${LEADTIME}" ]; then
        continue
    fi

    echo "Processing file: $gfs_file (forecast hour ${f_hour})..."
    grib_output="${TEMP_DIR}/gfs_${f_hour}.grb2"

    # Extract desired variables
    wgrib2 "$gfs_file" -match "${GFS_VARS}" -grib "$grib_output"

    # Determine step length (3h or 6h)
    if [ $((f_hour_num % 6)) -eq 0 ]; then
        step_seconds=21600
    else
        step_seconds=10800
    fi

    tp_step="${TEMP_DIR}/gfs_tp_${f_hour}.grb2"

    # Convert PRATE (kg/m2/s) → precipitation (mm)
    wgrib2 "$grib_output" \
        -match ":PRATE:surface:[0-9]*-[0-9]* hour ave fcst:" \
        -rpn "${step_seconds}:*" \
        -set_var "APCP" -set_lev "surface" -set_grib_type simple \
        -set_ftime "${f_hour} hour fcst" \
        -grib_out "$tp_step"

    # Initialize cumulative baseline if missing
    if [ ! -s "$tp_cumulative" ]; then
        init_zero_base "$grib_output"
    fi

    # Add new step to cumulative total
    if [ -s "$tp_step" ]; then
        wgrib2 "$tp_cumulative" -match ":APCP:" -rpn sto_1 \
        -import_grib "$tp_step" -match ":APCP:" -rpn rcl_1:+ \
        -set_var "APCP" -set_lev "surface" \
        -set_grib_type simple -set_ftime "${f_hour} hour fcst" \
        -grib_out "${tp_cumulative}.new"
        mv "${tp_cumulative}.new" "$tp_cumulative"
    fi

    # Merge cumulative APCP with other fields
    wgrib2 "$grib_output" -not_if ":PRATE:" -not_if ":APCP:" -grib "${grib_output}.tmp"
    if command -v grib_copy >/dev/null 2>&1; then
        grib_copy "${grib_output}.tmp" "$tp_cumulative" "${grib_output}"
    else
        cat "${grib_output}.tmp" "$tp_cumulative" > "${grib_output}"
    fi
    rm -f "${grib_output}.tmp"

    echo "Created cumulative precip: $grib_output"
done

echo "Combining GFS single-step files into one multi-step GRIB..."
# Temporary list of files to combine
GRB_LIST=()
for f_hour in $(seq -f "%03g" 0 3 ${LEADTIME}); do
    if [ -f "${TEMP_DIR}/gfs_${f_hour}.grb2" ]; then
        GRB_LIST+=("${TEMP_DIR}/gfs_${f_hour}.grb2")
    fi
done

# Define the combined output filename (based on init datetime)
INIT_DATETIME="${year}${month}${day}${cycle}"
COMBINED_FILE="${FORECAST_DIR}/gfs_${INIT_DATETIME}"

# Combine all GRIB files into one multi-step GRIB
grib_copy "${GRB_LIST[@]}" "${COMBINED_FILE}"

echo "Created combined GFS file: ${COMBINED_FILE}"
echo "GFS processing completed."

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
# Step 4: Perform verification on Wednesday at 12 UTC
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
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${SEVEN_DAYS_AGO} --end_date ${VERIF_START} #weekly (past 7 days)
    Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${THIRTY_DAYS_AGO} --end_date ${VERIF_START} #past 30 days

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
        Rscript ${VERIFICATION_SCRIPTS}/verify_parameters.R --start_date ${season_start} --end_date ${season_end} #seasonal
    fi

else
    echo "Not Wednesday at 12 UTC - skipping verification process"
fi

##########################################################################
# Step 5: Clean up
##########################################################################
echo "Cleaning up files..."

rm -rf ${TEMP_DIR}/*
rm -f ${FORECAST_DIR}/gfs*

echo "Verification process completed successfully!"

