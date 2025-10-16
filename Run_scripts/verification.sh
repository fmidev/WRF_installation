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

# Define the list of variables to extract
GFS_VARS=':TMP:2 m above ground:|:PRES:surface:|:HGT:surface:|:UGRD:10 m above ground:|:VGRD:10 m above ground:|:SPFH:2 m above ground:|:PRATE:surface:'

# Extract variables to GRIB
echo "Extracting GFS variables..."
for gfs_file in ${GFS_DIR}/gfs.t${cycle}z.pgrb2.0p25.f*; do
    if [ -f "$gfs_file" ]; then
        f_hour=$(basename "$gfs_file" | sed 's/.*\.f\([0-9]*\)$/\1/')
        if [ "${f_hour}" -gt "${LEADTIME}" ]; then
            continue
        fi
        echo "Processing file: $gfs_file (forecast hour ${f_hour})..."

        # Extract selected variables to a new GRIB file
        grib_output="${TEMP_DIR}/gfs_${f_hour}.grb2"
        
        wgrib2 "$gfs_file" \
            -match "${GFS_VARS}" \
            -grib "${grib_output}"

        # Calculate Total Precipitation from PRATE
        if [ -s "$grib_output" ]; then
            tp_cumulative="${TEMP_DIR}/gfs_tp_cumulative.grb2"
            tp_base_6h="${TEMP_DIR}/gfs_tp_base_6h.grb2"  # Stores cumulative at last 6h mark
            
            f_hour_num=$((10#${f_hour}))
            
            # For f000, initialize with zero
            if [ "${f_hour}" = "000" ]; then
                wgrib2 "$grib_output" -match ":PRATE:surface:anl:" \
                    -set_var "APCP" -set_lev "surface" -set_grib_type simple -grib_out "$tp_cumulative"
            else
                if [ $((f_hour_num % 6)) -eq 0 ]; then
                    # 6-hour mark: use the 6h averaged PRATE field
                    wgrib2 "$grib_output" -match ":PRATE:surface:.*ave fcst:" -rpn "21600:*" \
                        -set_var "APCP" -set_lev "surface" -set_grib_type simple -grib_out "${TEMP_DIR}/gfs_tp_6h.grb2"
                    
                    # Add this 6h period to the base from the previous 6h mark
                    if [ -s "$tp_base_6h" ]; then
                        cat "$tp_base_6h" "${TEMP_DIR}/gfs_tp_6h.grb2" | wgrib2 - -rpn "sto_1:-1:sto_2:rcl_1:rcl_2:+" -grib_out "$tp_cumulative"
                    else
                        cp "${TEMP_DIR}/gfs_tp_6h.grb2" "$tp_cumulative"
                    fi
                    # Update the base for next cycle
                    cp "$tp_cumulative" "$tp_base_6h"
                else
                    # 3-hour mark: use the 3h averaged PRATE field
                    wgrib2 "$grib_output" -match ":PRATE:surface:.*ave fcst:" -rpn "10800:*" \
                        -set_var "APCP" -set_lev "surface" -set_grib_type simple -grib_out "${TEMP_DIR}/gfs_tp_3h.grb2"
                    
                    # Add this 3h period to the base from the last 6h mark
                    if [ -s "$tp_base_6h" ]; then
                        cat "$tp_base_6h" "${TEMP_DIR}/gfs_tp_3h.grb2" | wgrib2 - -rpn "sto_1:-1:sto_2:rcl_1:rcl_2:+" -grib_out "$tp_cumulative"
                    else
                        cp "${TEMP_DIR}/gfs_tp_3h.grb2" "$tp_cumulative"
                    fi
                fi
            fi
            
            # Remove PRATE and APCP from grib_output, then add our cumulative APCP
            wgrib2 "$grib_output" -not_if ":PRATE:" -not_if ":APCP:" -grib "${grib_output}.tmp"
            cat "${grib_output}.tmp" "$tp_cumulative" > "$grib_output"
            rm -f "${grib_output}.tmp"
        fi

        echo "Successfully created: $grib_output"
    else
        echo "File not found: $gfs_file"
    fi
done

# Move processed files to forecast directory with proper naming
echo "Moving GFS files to forecast directory..."
for f_hour in $(seq -f "%03g" 0 3 ${LEADTIME}); do
    if [ -f "${TEMP_DIR}/gfs_${f_hour}.grb2" ]; then
        # Calculate the valid time for this forecast hour
        f_hour_num=$((10#${f_hour}))
        valid_time=$(date -u -d "${year}-${month}-${day} ${cycle}:00:00 UTC +${f_hour_num} hours" +'%Y%m%d%H')
        mv "${TEMP_DIR}/gfs_${f_hour}.grb2" "${FORECAST_DIR}/gfs_${valid_time}"
        echo "Created: ${FORECAST_DIR}/gfs_${valid_time}"
    fi
done

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
# Step 5: Clean up
##########################################################################
echo "Cleaning up files..."

rm -rf ${TEMP_DIR}/*
rm -f ${FORECAST_DIR}/gfs*

echo "Verification process completed successfully!"

