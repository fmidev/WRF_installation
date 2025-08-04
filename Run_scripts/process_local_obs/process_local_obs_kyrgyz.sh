#!/bin/bash

# ===============================================
# Process local observations for WRF DA and verification in kyrgyzstan
# Author: Mikael Hasu
# Date: August 2025
# ===============================================

# Check for required arguments
if [ "$#" -lt 5 ]; then
    echo "Usage: $0 YYYY MM DD HH DA_DIR BASE_DIR"
    exit 1
fi

# Input variables
YYYY=$1  # Year
MM=$2    # Month
DD=$3    # Day
HH=$4    # Hour
DA_DIR=$5
BASE_DIR=$6

# Calculate observation time (local time)
AHEAD_HOURS=8
AHEAD_DATE=$(date -d "${YYYY}-${MM}-${DD} ${HH}:00:00 ${AHEAD_HOURS} hours" "+%Y%m%d%H")
AHEAD_YYYY=${AHEAD_DATE:0:4}
AHEAD_MM=${AHEAD_DATE:4:2}
AHEAD_DD=${AHEAD_DATE:6:2}
AHEAD_HH=${AHEAD_DATE:8:2}

echo "copying obs from smartmet server..."
rsync -av smartmet@IP:/smartmet/data/incoming/kyrgyz_local_obs/kyrgyz_local_obs${AHEAD_YYYY}${AHEAD_MM}${AHEAD_DD}${AHEAD_HH}00.csv $DA_DIR/ob/raw_obs/kyrgyz_local_obs${YYYY}${MM}${DD}${HH}00.csv

# Combine downloaded observations with station list by station id for verification
Verif_obs="${BASE_DIR}/Verification/Data/Obs/local_obs${YYYY}${MM}${DD}${HH}00_verif.csv"
Raw_obs="${DA_DIR}/ob/raw_obs/kyrgyz_local_obs${YYYY}${MM}${DD}${HH}00.csv"
Station_file="${BASE_DIR}/Verification/Data/Static/stationlist_KYR.csv"

# Create an assimilation observation file
Assim_obs="${DA_DIR}/ob/raw_obs/${YYYY}${MM}${DD}${HH}_local_obs.csv"

if [ -f "$Raw_obs" ] && [ -f "$Station_file" ]; then
    echo "Combining $Raw_obs and $Station_file into $Verif_obs"
    awk -F, '
    NR==FNR && FNR>1 { sid=$1; lat=$2; lon=$3; elev=$4; name=$5; stations[sid]=lat","lon","elev; next }
    FNR==1 { next } # skip header in obs file
    {
        sid=$1
        dttm=$2
        t2m=$3
        rh2=$4
        wspd=$5
        wdir=$6
        slp=$7
        pres=$8
        td2=$9
        split(stations[sid],s,",")
        if(length(stations[sid])>0) {
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", dttm, sid, s[1], s[2], s[3], t2m, td2, pres, "", wdir, wspd
        }
    }
    ' "$Station_file" "$Raw_obs" | awk 'BEGIN{print "valid_dttm\tSID\tlat\tlon\telev\tT2m\tTd2m\tPressure\tPcp\tWdir\tWS"}1' > "$Verif_obs"
    echo "Verification observation created: $Verif_obs"

    # Create assimilation observation file with required format
    echo "Creating assimilation observation file: $Assim_obs"
    awk -F, '
    NR==FNR && FNR>1 { sid=$1; lat=$2; lon=$3; elev=$4; name=$5; stations[sid]=lat","lon","elev","name; next }
    FNR==1 { next } # skip header in obs file
    {
        sid=$1
        dttm=$2
        t2m=$3
        rh2=$4
        wspd=$5
        wdir=$6
        slp=$7
        pres=$8
        td2=$9
        split(stations[sid],s,",")
        if(length(stations[sid])>0) {
            # Format date as YYYY-MM-DD_HH:MM:SS
            split(dttm, dt, "T")
            date_part = dt[1]
            time_part = dt[2]
            if (length(time_part) == 0) time_part = "00:00:00"
            formatted_date = date_part "_" time_part

            # Use pressure or sea level pressure depending on availability
            p_value = pres
            if (p_value == "") p_value = slp
            if (p_value == "NA") p_value = slp

            # Convert height to numeric if available from station data
            height = s[3];

            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                   sid, s[1], s[2], formatted_date, slp, p_value, height, t2m, rh2, wspd, wdir
        }
    }
    ' "$Station_file" "$Raw_obs" | awk 'BEGIN{print "station_id\tlatitude\tlongitude\tdate\tsea_level_pressure\tpressure\theight\ttemperature\trelative_humidity\twind_speed\twind_direction"}1' > "$Assim_obs"
    echo "Assimilation observation created: $Assim_obs"
else
    echo "Observation or station file missing, cannot combine."
fi

# Return 0 for success, 1 for failure
if [ -f "$Assim_obs" ]; then
    exit 0
else
    exit 1
fi
