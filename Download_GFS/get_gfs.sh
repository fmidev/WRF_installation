#!/bin/bash
#
# ===============================================
# GFS download for WRF model
# Author: Mikael Hasu
# Date: November 2024
# ===============================================
#

# Load configuration if available
CONFIG_FILE="gfs.cnf"
. /home/wrf/WRF_Model/scripts/$CONFIG_FILE

# Default Configuration
: "${AREA:=world}"
: "${TOP:=90}"
: "${BOTTOM:=-90}"
: "${LEFT:=0}"
: "${RIGHT:=360}"
: "${INTERVALS:=0 3 96}"
: "${RESOLUTION:=0p25}"
: "${VALID_HOURS:=00|06|12|18}"

# Parse command-line options
while getopts "a:b:dg:i:l:r:t:v" flag; do
    case "$flag" in
        a) AREA=$OPTARG;;
        d) DRYRUN=1;;
        g) RESOLUTION=$OPTARG;;
        i) INTERVALS=("$OPTARG");;
        l) LEFT=$OPTARG;;
        r) RIGHT=$OPTARG;;
        t) TOP=$OPTARG;;
        b) BOTTOM=$OPTARG;;
        v) VALID_HOURS=$OPTARG;;
    esac
done

# Constants and Variables
STEP=6
BASE="/home/wrf/WRF_Model"
TMP="$BASE/tmp/gfs_${AREA}_${RESOLUTION}_$(date -u +%Y%m%d%H%M)"
LOGFILE="$BASE/logs/gfs_${AREA}_$(date -u +%H).log"
OUTNAME="$(date -u +%Y%m%d%H%M)_gfs_$AREA"

# Model Reference Time Calculation
RT=$(date -u +%s -d '-3 hours')
RT=$((RT / (STEP * 3600) * (STEP * 3600)))
RT_DATE=$(date -u -d@$RT +%Y%m%d)
RT_HOUR=$(date -u -d@$RT +%H)
RT_DATE_HH=$(date -u -d@$RT +%Y%m%d%H)
RT_DATE_HHMM=$(date -u -d@$RT +%Y%m%d%H%M)
RT_ISO=$(date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ)

# Redirect output to log file if not running interactively
[ "$TERM" = "dumb" ] && exec &> "$LOGFILE"

echo "Model Reference Time: $RT_ISO"
echo "Resolution: $RESOLUTION"
echo "Area: $AREA (left:$LEFT, right:$RIGHT, top:$TOP, bottom:$BOTTOM)"
echo "Intervals: ${INTERVALS[*]}"
echo "Temporary Directory: $TMP"

# Create temporary directory if not in dry run
[ -z "$DRYRUN" ] && mkdir -p "$TMP/grb"

# Logging Function
log() {
    echo "$(date -u +%H:%M:%S) $1"
}

# Background Download Execution
runBackground() {
    downloadStep "$1" &
    ((dnum = dnum + 1))
    ((dnum % 6 == 0)) && wait
}

# Test File Validity
testFile() {
    local file="$1"
    if [ -s "$file" ]; then
        grib_count "$file" &>/dev/null
        [ $? -eq 0 ] && [ "$(grib_count "$file")" -gt 0 ] && return 0
        rm -f "$file"
    fi
    return 1
}

# Download File Step
downloadStep() {
    local step=$(printf '%03d' "$1")
    local file

    if [ "$RESOLUTION" == "0p50" ]; then
        file="gfs.t${RT_HOUR}z.pgrb2full.${RESOLUTION}.f${step}"
    else
        file="gfs.t${RT_HOUR}z.pgrb2.${RESOLUTION}.f${step}"
    fi

    if testFile "$TMP/grb/$file"; then
        log "Cached file: $file (size: $(stat --printf='%s' "$TMP/grb/$file"), messages: $(grib_count "$TMP/grb/$file"))"
        return
    fi

    local count=0
    while true; do
        ((count++))
        log "Downloading file: $file (try: $count)"
        curl -s -S -o "$TMP/grb/$file" "$(buildURL "$file")"
        if testFile "$TMP/grb/$file"; then
            log "Downloaded: $file (size: $(stat --printf='%s' "$TMP/grb/$file"), messages: $(grib_count "$TMP/grb/$file"))"
            syncFile "$file"
            break
        fi
        [ $count -eq 60 ] && break
        sleep 60
    done
}

# Build Download URL
buildURL() {
    local file="$1"
    echo "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_${RESOLUTION}.pl?file=${file}&lev_1_mb=on&lev_2_mb=on&lev_3_mb=on&lev_5_mb=on&lev_7_mb=on&lev_10_mb=on&lev_15_mb=on&lev_20_mb=on&lev_30_mb=on&lev_40_mb=on&lev_50_mb=on&lev_70_mb=on&lev_100_mb=on&lev_150_mb=on&lev_200_mb=on&lev_250_mb=on&lev_300_mb=on&lev_350_mb=on&lev_400_mb=on&lev_450_mb=on&lev_500_mb=on&lev_550_mb=on&lev_600_mb=on&lev_650_mb=on&lev_700_mb=on&lev_750_mb=on&lev_800_mb=on&lev_850_mb=on&lev_900_mb=on&lev_925_mb=on&lev_950_mb=on&lev_975_mb=on&lev_1000_mb=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&lev_mean_sea_level=on&lev_entire_atmosphere=on&lev_entire_atmosphere_%5C%28considered_as_a_single_layer%5C%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_convective_cloud_layer=on&lev_0-0.1_m_below_ground=on&lev_0.1-0.4_m_below_ground=on&lev_0.4-1_m_below_ground=on&lev_1-2_m_below_ground=on&lev_1000_mb=on&lev_tropopause=on&lev_max_wind=on&lev_80_m_above_ground=on&var_CAPE=on&var_CIN=on&var_GUST=on&var_HGT=on&var_ICEC=on&var_LAND=on&var_PEVPR=on&var_PRATE=on&var_PRES=on&var_PRMSL=on&var_PWAT=on&var_RH=on&var_SHTFL=on&var_SNOD=on&var_SOILW=on&var_TSOIL=on&var_MSLET=on&var_SPFH=on&var_TCDC=on&var_TMP=on&var_DPT=on&var_UGRD=on&var_VGRD=on&var_DZDT=on&var_CNWAT=on&var_WEASD=on&subregion=&leftlon=${LEFT}&rightlon=${RIGHT}&toplat=${TOP}&bottomlat=${BOTTOM}&dir=%2Fgfs.${RT_DATE}%2F${RT_HOUR}%2Fatmos"
}

# Sync File to Destination
syncFile() {
    local file="$1"
    if [ -n "$WRF_COPY_DEST" ] && [[ $RT_HOUR =~ $VALID_HOURS ]]; then
        rsync -ra "$TMP/grb/$file" "$WRF_COPY_DEST/$RT_DATE_HH/"
    fi
}

# Download Intervals
for interval in "${INTERVALS[@]}"; do
    log "Downloading interval $interval"
    # Split interval into start, step, and end
    start=$(echo "$interval" | cut -d' ' -f1)
    step=$(echo "$interval" | cut -d' ' -f2)
    end=$(echo "$interval" | cut -d' ' -f3)

    # Validate and process intervals
    if [[ -n "$start" && -n "$step" && -n "$end" ]]; then
        for i in $(seq "$start" "$step" "$end"); do
            [ -n "$DRYRUN" ] && echo -n "$i " || runBackground "$i"
        done
        [ -n "$DRYRUN" ] && echo ""
    else
        log "Invalid interval format: $interval"
    fi
done

[ -n "$DRYRUN" ] && exit

# Wait for all background processes
wait

log "Download complete. Size: $(du -hs "$TMP/grb/" | cut -f1), Files: $(ls -1 "$TMP/grb/" | wc -l)"

# Cleanup Temporary Files
rm -f $TMP/*_gfs_*
rm -f $TMP/*.txt
rm -f $TMP/grb/gfs*
rmdir $TMP/grb
rmdir $TMP
