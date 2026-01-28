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
CURRENT_DATE=$(date -u +%Y%m%d)
CURRENT_HOUR=$(date -u +%H)
LOGFILE="$BASE/logs/ecmwf_${CURRENT_HOUR}.log"

# Clean up old log files from previous days
if [ -d "$BASE/logs" ]; then
    for old_log in "$BASE/logs"/ecmwf_*.log; do
        [ ! -f "$old_log" ] && continue
        # Get the file's modification date (YYYYMMDD)
        FILE_DATE=$(date -r "$old_log" +%Y%m%d 2>/dev/null)
        # Remove if from a previous day
        if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" != "$CURRENT_DATE" ]; then
            rm -f "$old_log"
        fi
    done
fi

# Logging Function
log() {
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') $1"
}

# Function to determine the most recent available ECMWF forecast
get_latest_forecast_time() {
    local current_date=$(date -u +%Y%m%d)
    local yesterday=$(date -u -d 'yesterday' +%Y%m%d)
    
    # List of possible cycles to check (newest first)
    local cycles=("18" "12" "06" "00")
    local dates=("$current_date" "$yesterday")
    
    log "Checking for latest available ECMWF forecast..."
    
    # Try each date and cycle combination
    for check_date in "${dates[@]}"; do
        for check_hour in "${cycles[@]}"; do
            # Determine MODEL_TYPE based on cycle time
            local check_type="oper"
            if [ "$check_hour" = "06" ] || [ "$check_hour" = "18" ]; then
                check_type="scda"
            fi
            
            # Build test URL for 0-hour file
            local test_url="https://data.ecmwf.int/forecasts/${check_date}/${check_hour}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${check_type}/${check_date}${check_hour}0000-0h-${check_type}-fc.grib2"
            
            # Check if file exists using HTTP HEAD request
            if command -v curl &> /dev/null; then
                if curl -f -s -I --max-time 10 "$test_url" >/dev/null 2>&1; then
                    RT_DATE="$check_date"
                    RT_HOUR="$check_hour"
                    MODEL_TYPE="$check_type"
                    RT=$(date -u +%s -d "${RT_DATE:0:4}-${RT_DATE:4:2}-${RT_DATE:6:2} ${RT_HOUR}:00:00")
                    log "Found available forecast: ${RT_DATE} ${RT_HOUR}z (${MODEL_TYPE})"
                    return 0
                fi
            elif command -v wget &> /dev/null; then
                if wget -q --spider --timeout=10 "$test_url" 2>/dev/null; then
                    RT_DATE="$check_date"
                    RT_HOUR="$check_hour"
                    MODEL_TYPE="$check_type"
                    RT=$(date -u +%s -d "${RT_DATE:0:4}-${RT_DATE:4:2}-${RT_DATE:6:2} ${RT_HOUR}:00:00")
                    log "Found available forecast: ${RT_DATE} ${RT_HOUR}z (${MODEL_TYPE})"
                    return 0
                fi
            fi
        done
    done
}

# Get the latest available forecast time
get_latest_forecast_time

RT_DATE_HH="${RT_DATE}${RT_HOUR}"
RT_ISO=$(date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ)


# Set download directory
INCOMING_TMP="$BASE/ECMWF/$RT_DATE$RT_HOUR"

# Redirect output to log file if not running interactively
if [ "$TERM" = "dumb" ]; then
    mkdir -p "$BASE/logs"
    exec &>> "$LOGFILE"
    echo "" # Add blank line between runs
    echo "=========================================="
    echo "New run started: $(date -u '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
fi

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

# Check if download should proceed based on valid hours
if [[ ! $RT_HOUR =~ $VALID_HOURS ]]; then
    log "Skipping download - $RT_HOUR is not in valid hours ($VALID_HOURS)"
    exit 0
fi

# Check if data already exists and has been converted
if [ -f "$INCOMING_TMP/.converted" ]; then
    log "Data already exists and has been converted for $RT_DATE_HH"
    log "Marker file: $INCOMING_TMP/.converted"
    FILE_COUNT=$(ls -1 "$INCOMING_TMP"/*.grib2 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        log "Found $FILE_COUNT GRIB2 files already processed"
        log "Skipping download and conversion"
        exit 0
    else
        log "WARNING: Marker file exists but no GRIB2 files found, will re-download"
        rm -f "$INCOMING_TMP/.converted"
    fi
fi

# Create download directory if not in dry run
if [ -z "$DRYRUN" ]; then
    mkdir -p "$INCOMING_TMP"
else
    log "DRY RUN: Would create directory $INCOMING_TMP"
    log "DRY RUN: Would download from https://data.ecmwf.int/forecasts/${RT_DATE}/${RT_HOUR}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${MODEL_TYPE}/"
    exit 0
fi

# Check if curl or wget is available
DOWNLOADER=""
if command -v curl &> /dev/null; then
    DOWNLOADER="curl"
elif command -v wget &> /dev/null; then
    DOWNLOADER="wget"
else
    log "ERROR: Neither curl nor wget found. Please install one of them."
    exit 1
fi

# Download data from ECMWF HTTPS endpoint
log "Starting download from ECMWF HTTPS endpoint..."
BASE_URL="https://data.ecmwf.int/forecasts/${RT_DATE}/${RT_HOUR}z/${MODEL_PRODUCER}/${MODEL_VERSION}/${MODEL_TYPE}/"

log "Base URL: $BASE_URL"

# Download forecast files for hours 0 to MAX_FORECAST_HOUR
DOWNLOAD_SUCCESS=0
DOWNLOAD_FAILED=0

for hour in $(seq 0 3 $MAX_FORECAST_HOUR); do
    # Build filename: YYYYMMDDHH0000-Xh-TYPE-fc.grib2
    FILENAME="${RT_DATE}${RT_HOUR}0000-${hour}h-${MODEL_TYPE}-fc.grib2"
    FILE_URL="${BASE_URL}${FILENAME}"
    OUTPUT_FILE="${INCOMING_TMP}/${FILENAME}"
    
    log "Downloading forecast hour $hour: $FILENAME"
    
    if [ "$DOWNLOADER" = "curl" ]; then
        if curl -f -s -S --retry 3 --retry-delay 5 -o "$OUTPUT_FILE" "$FILE_URL"; then
            DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
            FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
            log "  ✓ Downloaded $FILENAME ($FILE_SIZE)"
        else
            DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
            log "  ✗ Failed to download $FILENAME"
            rm -f "$OUTPUT_FILE"
        fi
    else
        if wget -q --tries=3 --waitretry=5 -O "$OUTPUT_FILE" "$FILE_URL"; then
            DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
            FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
            log "  ✓ Downloaded $FILENAME ($FILE_SIZE)"
        else
            DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
            log "  ✗ Failed to download $FILENAME"
            rm -f "$OUTPUT_FILE"
        fi
    fi
done

log "Download summary: $DOWNLOAD_SUCCESS succeeded, $DOWNLOAD_FAILED failed"

if [ $DOWNLOAD_SUCCESS -gt 0 ]; then
    log "Download complete."
    
    # Get download statistics
    FILE_COUNT=$(ls -1 "$INCOMING_TMP"/*.grib2 2>/dev/null | wc -l)
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
        log "Base URL attempted: $BASE_URL"
        exit 1
    fi
else
    log "ERROR: All downloads failed."
    log "Base URL attempted: $BASE_URL"
    exit 1
fi

log "ECMWF download process completed successfully."