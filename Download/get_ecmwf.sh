#!/bin/bash
#
# ===============================================
# ECMWF download for WRF model
# Author: Mikael Hasu
# Date: January 2026
# ===============================================
#

# Load configuration if available
CONFIG_FILE="ecmwf.cnf"
if [ -f "/home/wrf/WRF_Model/scripts/$CONFIG_FILE" ]; then
    . /home/wrf/WRF_Model/scripts/$CONFIG_FILE
fi

# Default Configuration
: "${MODEL_PRODUCER:=ifs}"
: "${MODEL_VERSION:=0p25}"
: "${VALID_HOURS:=00|06|12|18}"
: "${MAX_FORECAST_HOUR:=72}"

# Parse command-line options
while getopts "dp:v:h:f:" flag; do
    case "$flag" in
        d) DRYRUN=1;;
        p) MODEL_PRODUCER=$OPTARG;;
        v) MODEL_VERSION=$OPTARG;;
        h) VALID_HOURS=$OPTARG;;
        f) MAX_FORECAST_HOUR=$OPTARG;;
    esac
done

# Constants and Variables
BASE="/home/wrf/WRF_Model"
LOGFILE="$BASE/logs/ecmwf_$(date -u +%H).log"

# Function to determine the most recent available ECMWF forecast
# Ready times (UTC): 00z at 07:55, 06z at 13:15, 12z at 19:55, 18z at 01:15
get_latest_forecast_time() {
    local current_time=$(date -u +%s)
    local current_hour=$(date -u +%H)
    local current_minute=$(date -u +%M)
    local current_date=$(date -u +%Y%m%d)
    
    # Convert current time to minutes since midnight
    local current_minutes=$((10#$current_hour * 60 + 10#$current_minute))
    
    # Define ready times in minutes since midnight and their corresponding cycle hours
    # 00z ready at 07:55 (475 minutes)
    # 06z ready at 13:15 (795 minutes)
    # 12z ready at 19:55 (1195 minutes)
    # 18z ready at 01:15 next day (75 minutes)
    
    if [ $current_minutes -ge 475 ] && [ $current_minutes -lt 795 ]; then
        # Between 07:55 and 13:15 - use 00z from today
        RT_HOUR="00"
        RT_DATE="$current_date"
    elif [ $current_minutes -ge 795 ] && [ $current_minutes -lt 1195 ]; then
        # Between 13:15 and 19:55 - use 06z from today
        RT_HOUR="06"
        RT_DATE="$current_date"
    elif [ $current_minutes -ge 1195 ]; then
        # After 19:55 - use 12z from today
        RT_HOUR="12"
        RT_DATE="$current_date"
    else
        # Before 07:55 - use 18z from previous day
        RT_HOUR="18"
        RT_DATE=$(date -u -d 'yesterday' +%Y%m%d)
    fi
    
    # Calculate RT timestamp
    RT=$(date -u +%s -d "${RT_DATE:0:4}-${RT_DATE:4:2}-${RT_DATE:6:2} ${RT_HOUR}:00:00")
}

# Get the latest available forecast time
get_latest_forecast_time

RT_DATE_HH="${RT_DATE}${RT_HOUR}"
RT_ISO=$(date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ)

# Determine MODEL_TYPE based on cycle time
# 06/18z use scda (short cut-off), 00/12z use oper (operational)
if [ "$RT_HOUR" -eq 06 ] || [ "$RT_HOUR" -eq 18 ]; then
    MODEL_TYPE=scda
else
    MODEL_TYPE=oper
fi

# Set download directory
INCOMING_TMP="$BASE/ECMWF/$RT_DATE$RT_HOUR"

# Redirect output to log file if not running interactively
[ "$TERM" = "dumb" ] && exec &> "$LOGFILE"

echo "============================================="
echo "ECMWF Data Download"
echo "============================================="
echo "Current Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Latest Available Forecast: $RT_ISO (${RT_HOUR}z cycle)"
echo "Model Producer: $MODEL_PRODUCER"
echo "Model Version: $MODEL_VERSION"
echo "Model Type: $MODEL_TYPE"
echo "Max Forecast Hour: $MAX_FORECAST_HOUR"
echo "Download Directory: $INCOMING_TMP"
echo "============================================="

# Logging Function
log() {
    echo "$(date -u +%H:%M:%S) $1"
}

# Check if download should proceed based on valid hours
if [[ ! $RT_HOUR =~ $VALID_HOURS ]]; then
    log "Skipping download - $RT_HOUR is not in valid hours ($VALID_HOURS)"
    exit 0
fi

# Create download directory if not in dry run
if [ -z "$DRYRUN" ]; then
    mkdir -p "$INCOMING_TMP"
else
    log "DRY RUN: Would create directory $INCOMING_TMP"
    log "DRY RUN: Would download from s3://ecmwf-forecasts/${RT_DATE}/${RT_HOUR}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${MODEL_TYPE}/"
    exit 0
fi

# Check if aws CLI is available
if ! command -v aws &> /dev/null; then
    log "ERROR: AWS CLI not found. Please install it first."
    exit 1
fi

# Download data from S3 bucket
log "Starting download from ECMWF S3 bucket..."
S3_PATH="s3://ecmwf-forecasts/${RT_DATE}/${RT_HOUR}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${MODEL_TYPE}/"

# Build include patterns for forecast hours 0 to MAX_FORECAST_HOUR
# ECMWF files are named: YYYYMMDDHH0000-Xh-TYPE-fc.grib2
INCLUDE_PATTERNS=""
for hour in $(seq 0 $MAX_FORECAST_HOUR); do
    # Match pattern: YYYYMMDDHH0000-Xh-TYPE-fc.grib2
    INCLUDE_PATTERNS="$INCLUDE_PATTERNS --include *-${hour}h-*.grib2"
done

if aws s3 sync --exclude "*" $INCLUDE_PATTERNS --no-sign-request "$S3_PATH" "$INCOMING_TMP/"; then
    log "Download complete."
    
    # Get download statistics
    FILE_COUNT=$(ls -1 "$INCOMING_TMP" 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        TOTAL_SIZE=$(du -hs "$INCOMING_TMP" | cut -f1)
        log "Downloaded $FILE_COUNT files, total size: $TOTAL_SIZE"
        
        # List downloaded files
        log "Downloaded files:"
        ls -lh "$INCOMING_TMP"
        
        # Convert GRIB2 files from CCSDS compression to simple packing for WPS compatibility
        log "Converting GRIB2 files to WPS-compatible format..."
        if command -v wgrib2 &> /dev/null; then
            CONVERTED=0
            FAILED=0
            
            # Check first file to see if conversion is needed
            FIRST_FILE=$(ls "$INCOMING_TMP"/*.grib2 2>/dev/null | head -1)
            if [ -n "$FIRST_FILE" ]; then
                PACKING=$(wgrib2 -d 1 -packing "$FIRST_FILE" 2>/dev/null | grep -o "packing=.*" | head -1)
                
                if [[ "$PACKING" == *"CCSDS"* ]] || [[ "$PACKING" == *"jpeg"* ]] || [[ "$PACKING" == *"complex"* ]]; then
                    log "  Files use $PACKING, converting to simple packing..."
                    
                    for grib_file in "$INCOMING_TMP"/*.grib2; do
                        [ ! -f "$grib_file" ] && continue
                        
                        filename=$(basename "$grib_file")
                        temp_file="${grib_file}.tmp"
                        
                        # Convert without verbose output for speed
                        if wgrib2 "$grib_file" -set_grib_type simple -grib_out "$temp_file" >/dev/null 2>&1; then
                            mv "$temp_file" "$grib_file"
                            CONVERTED=$((CONVERTED + 1))
                        else
                            rm -f "$temp_file"
                            FAILED=$((FAILED + 1))
                        fi
                    done
                    
                    log "Converted $CONVERTED GRIB2 files to simple packing"
                    if [ "$FAILED" -gt 0 ]; then
                        log "WARNING: Failed to convert $FAILED files"
                    fi
                    
                    # Create marker file to indicate conversion is complete
                    echo "Conversion completed at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$INCOMING_TMP/.converted"
                    echo "Files converted: $CONVERTED" >> "$INCOMING_TMP/.converted"
                    echo "Files failed: $FAILED" >> "$INCOMING_TMP/.converted"
                else
                    log "  Files already use compatible packing, no conversion needed"
                    # Still create marker file since files are ready to use
                    echo "No conversion needed at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$INCOMING_TMP/.converted"
                    echo "Files already in compatible format" >> "$INCOMING_TMP/.converted"
                fi
            fi
        else
            log "WARNING: wgrib2 not found, skipping GRIB2 conversion"
            log "ECMWF files may not work with WPS ungrib without conversion"
        fi
        
        # Copy to destination if configured
        if [ -n "$WRF_COPY_DEST" ]; then
            log "Copying files to $WRF_COPY_DEST/$RT_DATE$RT_HOUR/"
            mkdir -p "$WRF_COPY_DEST/$RT_DATE$RT_HOUR/"
            rsync -ra "$INCOMING_TMP/" "$WRF_COPY_DEST/$RT_DATE$RT_HOUR/"
            log "Copy complete."
        fi
    else
        log "WARNING: No files downloaded. Check if data is available."
        exit 1
    fi
else
    log "ERROR: Download failed."
    exit 1
fi

log "ECMWF download process completed successfully."