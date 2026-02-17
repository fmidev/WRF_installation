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

# Read domain settings from domain.txt
# ===============================================
DOMAIN_FILE="${MAIN_DIR}/domain.txt"

if [ ! -f "$DOMAIN_FILE" ]; then
  echo "Error: domain.txt not found at $DOMAIN_FILE"
  echo "Please save your WRF Domain Wizard namelist.wps file as domain.txt in the scripts directory"
  exit 1
fi

echo "Reading domain configuration from $DOMAIN_FILE"

# Parse the domain.txt file using Python script for all domains
eval $(${MAIN_DIR}/parse_namelist_wps.py $DOMAIN_FILE)

# Convert map projection name to obsproc numeric code and set projection-specific parameters
case "${MAP_PROJ,,}" in
    *lambert*)
        MAP_PROJ_CODE=1
        # Lambert: All parameters should be provided by parser
        ;;
    *mercator*)
        MAP_PROJ_CODE=3
        # Mercator projection requires truelat1 = 0 for obsproc to work correctly
        if [ "$(echo "$TRUELAT1 != 0" | bc -l)" -eq 1 ]; then
            echo "ERROR: Mercator projection with obsproc requires truelat1 = 0"
            echo "Current truelat1 value: ${TRUELAT1}"
            echo "Please update your domain"
            exit 1
        fi
        # Mercator: Only truelat1 is used
        TRUELAT2=0.0
        # stand_lon not used for mercator in obsproc
        STAND_LON=${REF_LON}
        ;;
    *lat-lon*|*latlon*|*cylindrical*)
        MAP_PROJ_CODE=0
        # For Lat-Lon, true latitudes are not used in obsproc
        TRUELAT1=0.0
        TRUELAT2=0.0
        ;;
    *)
        echo "ERROR: Unsupported map projection '${MAP_PROJ}'"
        echo "Supported projections: lambert, mercator, lat-lon"
        exit 1
        ;;
esac

# Base URL
BASE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/gdas.${YYYY}${MM}${DD}/"

# Files to download
FILES=(
    "gdas.t${HH}z.1bamua.tm00.bufr_d"    # AMSU-A
    "gdas.t${HH}z.eshrs3.tm00.bufr_d"    # HIRS-3
    "gdas.t${HH}z.1bhrs4.tm00.bufr_d"    # HIRS-4
    "gdas.t${HH}z.1bmhs.tm00.bufr_d"     # MHS
    "gdas.t${HH}z.airsev.tm00.bufr_d"    # AIRS
    "gdas.t${HH}z.atms.tm00.bufr_d"      # ATMS
    "gdas.t${HH}z.mtiasi.tm00.bufr_d"    # METOP IASI
    "gdas.t${HH}z.sevasr.tm00.bufr_d"    # SEVIRI All-Sky Radiances
    "gdas.t${HH}z.ssmisu.tm00.bufr_d"    # SSMIS
    "gdas.t${HH}z.gpsro.tm00.bufr_d.nr"  # GPS Radio Occultation
    "gdas.t${HH}z.prepbufr.nr"           # Conventional observations
)
# Create necessary directories with full path checking
echo "Creating necessary directories..."
for dir in "$DA_DIR/ob" "$DA_DIR/ob/raw_obs" "$DA_DIR/ob/obsproc" "$DA_DIR/ob/wrf_obs" "$DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}"; do
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "$dir" || { echo "ERROR: Failed to create directory $dir"; exit 1; }
    fi
done

# Also create needed verification directories
mkdir -p "${BASE_DIR}/Verification/Data/Obs" || { echo "ERROR: Failed to create directory ${BASE_DIR}/Verification/Data/Obs"; exit 1; }

# Download the files
cd "$DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}" || { echo "ERROR: Failed to change to directory $DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}"; exit 1; }

# Define file mapping (download name -> final name)
declare -A FILE_MAP=(
    ["gdas.t${HH}z.1bamua.tm00.bufr_d"]="amsua.bufr"
    ["gdas.t${HH}z.eshrs3.tm00.bufr_d"]="hirs3.bufr"
    ["gdas.t${HH}z.1bhrs4.tm00.bufr_d"]="hirs4.bufr"
    ["gdas.t${HH}z.1bmhs.tm00.bufr_d"]="mhs.bufr"
    ["gdas.t${HH}z.airsev.tm00.bufr_d"]="airs.bufr"
    ["gdas.t${HH}z.atms.tm00.bufr_d"]="atms.bufr"
    ["gdas.t${HH}z.mtiasi.tm00.bufr_d"]="iasi.bufr"
    ["gdas.t${HH}z.sevasr.tm00.bufr_d"]="seviri.bufr"
    ["gdas.t${HH}z.ssmisu.tm00.bufr_d"]="ssmis.bufr"
    ["gdas.t${HH}z.gpsro.tm00.bufr_d.nr"]="gpsro.bufr"
    ["gdas.t${HH}z.prepbufr.nr"]="ob.bufr"
)

for FILE in "${FILES[@]}"; do
    FINAL_NAME="${FILE_MAP[$FILE]}"
    
    # Check if the final file already exists
    if [ -f "$FINAL_NAME" ]; then
        echo "File $FINAL_NAME already exists, skipping download of ${FILE}"
    else
        URL="${BASE_URL}${FILE}"
        echo "Downloading ${FILE}..."
        curl -O "${URL}"
        
        # Rename if download was successful
        if [ -f "$FILE" ]; then
            mv "$FILE" "$FINAL_NAME"
            echo "Renamed $FILE to $FINAL_NAME"
        else
            echo "WARNING: Failed to download ${FILE}"
        fi
    fi
done

# Make sure obserr.txt exists
cd "$DA_DIR/ob/obsproc" || { echo "ERROR: Failed to change to directory $DA_DIR/ob/obsproc"; exit 1; }
if [ -f "$WRFDA_DIR/var/obsproc/obserr.txt" ]; then
    cp "$WRFDA_DIR/var/obsproc/obserr.txt" .
else
    echo "WARNING: Could not find obserr.txt at $WRFDA_DIR/var/obsproc/obserr.txt"
    echo "You may need to provide this file manually."
fi

# Set observation window
s_date="$YYYY-$MM-$DD ${HH}:00:00"
window=1
ob_window_min=$(date -d "$s_date $window hours ago" "+%Y-%m-%d %H:%M:%S")
ob_window_max=$(date -d "$s_date $window hours" "+%Y-%m-%d %H:%M:%S")
read minyear minmonth minday minhour minmin minsec <<< $(echo $ob_window_min | tr '-' ' ' | tr ':' ' ')
read maxyear maxmonth maxday maxhour maxmin maxsec <<< $(echo $ob_window_max | tr '-' ' ' | tr ':' ' ')

# Build record8 configuration before writing namelist
# For record7: XLONC should be the domain center, STANDARD_LON is the projection standard meridian
# Determine IDD based on projection type and whether domain center differs from projection center
if [ "$MAP_PROJ_CODE" -eq 1 ]; then
    # Lambert Conformal: Check if domain center differs from projection center
    if [ "$(echo "$REF_LON != $STAND_LON" | bc -l)" -eq 1 ]; then
        IDD=2
    else
        IDD=1
    fi
else
    IDD=1
fi

NESTIX=$(( E_WE[0] - 1 ))
NESTJX=$(( E_SN[0] - 1 ))
CENTER_I=$(( (NESTIX + 1) / 2 )) 
CENTER_J=$(( (NESTJX + 1) / 2 ))  
DIS_KM=$(printf "%.3f" "$(bc <<< "$DX/1000")")

cat << EOF > namelist.obsproc
&record1
 obs_gts_filename       = 'obs.${YYYY}${MM}${DD}${HH}',
 obs_err_filename       = 'obserr.txt',
 fg_format              = 'WRF',
 gts_from_mmm_archive   = .false.
/

&record2
 time_window_min  = '${minyear}-${minmonth}-${minday}_${minhour}:00:00',
 time_analysis    = '${YYYY}-${MM}-${DD}_${HH}:00:00',
 time_window_max  = '${maxyear}-${maxmonth}-${maxday}_${maxhour}:00:00',
/

&record3
 max_number_of_obs        = 400000,
 fatal_if_exceed_max_obs  = .TRUE.,
/

&record4
 qc_test_vert_consistency = .TRUE.,
 qc_test_convective_adj   = .TRUE.,
 qc_test_above_lid        = .TRUE.,
 remove_above_lid         = .false.,
 domain_check_h           = .true.,
 Thining_SATOB            = .false.,
 Thining_SSMI             = .false.,
 Thining_QSCAT            = .false.,
 calc_psfc_from_qnh       = .true.,
/

&record5
 print_gts_read           = .TRUE.,
 print_gpspw_read         = .TRUE.,
 print_recoverp           = .TRUE.,
 print_duplicate_loc      = .TRUE.,
 print_duplicate_time     = .TRUE.,
 print_recoverh           = .TRUE.,
 print_qc_vert            = .TRUE.,
 print_qc_conv            = .TRUE.,
 print_qc_lid             = .TRUE.,
 print_uncomplete         = .TRUE.,
/

&record6
 ptop            = 1000.0,
 base_pres       = 100000.0,
 base_temp       = 290.0,
 base_lapse      = 50.0,
 base_strat_temp = 215.0,
 base_tropo_pres = 20000.0
/

&record7
 IPROJ = ${MAP_PROJ_CODE},
 PHIC  = ${REF_LAT},
 XLONC = ${REF_LON},
 TRUELAT1= ${TRUELAT1},
 TRUELAT2= ${TRUELAT2},
 MOAD_CEN_LAT = ${REF_LAT},
 STANDARD_LON = ${STAND_LON},
/

&record8
 IDD    = ${IDD},
 MAXNES = 1,
 NESTIX = ${NESTIX},
 NESTJX = ${NESTJX},
 DIS    = ${DIS_KM},
 NUMC   = 1,
 NESTI  = ${CENTER_I},
 NESTJ  = ${CENTER_J},
 /

 &record9
 PREPBUFR_OUTPUT_FILENAME = 'prepbufr_output_filename',
 PREPBUFR_TABLE_FILENAME = 'prepbufr_table_filename',
 OUTPUT_OB_FORMAT = 2
 use_for          = '3DVAR',
 num_slots_past   = 3,
 num_slots_ahead  = 3,
 write_synop = .true.,
 write_ship  = .true.,
 write_metar = .true.,
 write_buoy  = .true.,
 write_pilot = .true.,
 write_sound = .true.,
 write_amdar = .true.,
 write_satem = .true.,
 write_satob = .true.,
 write_airep = .true.,
 write_gpspw = .true.,
 write_gpsztd= .true.,
 write_gpsref= .true.,
 write_gpseph= .true.,
 write_ssmt1 = .true.,
 write_ssmt2 = .true.,
 write_ssmi  = .true.,
 write_tovs  = .true.,
 write_qscat = .true.,
 write_profl = .true.,
 write_bogus = .true.,
 write_airs  = .true.,
 /
EOF
echo "Generated namelist.obsproc"

# Process local observations if country-specific script exists
echo "Processing local observations..."
COUNTRY_SCRIPT="$MAIN_DIR/process_local_obs_${COUNTRY}.sh"

if [ -f "$COUNTRY_SCRIPT" ]; then
    echo "Found country-specific processing script: $COUNTRY_SCRIPT"
    bash "$COUNTRY_SCRIPT" $YYYY $MM $DD $HH $DA_DIR $BASE_DIR
    PROCESS_EXIT_CODE=$?
    if [ $PROCESS_EXIT_CODE -ne 0 ]; then
        echo "WARNING: Country-specific observation processing failed with exit code $PROCESS_EXIT_CODE"
    fi
else
    echo "Country-specific processing script not found: $COUNTRY_SCRIPT"
    echo "Skipping local observation processing."
fi

# Check for local observations file and convert to little_r format if it exists
LOCAL_OBS_FILE="${DA_DIR}/ob/raw_obs/local_obs_${YYYY}${MM}${DD}${HH}.csv"
STATION_FILE="${BASE_DIR}/Verification/Data/Static/stationlist.csv"
OBSPROC_DIR="${DA_DIR}/ob/obsproc"
#Run obsproc if local observations file exists
if [ -f "$LOCAL_OBS_FILE" ]; then
    echo "Local observations file found: ${LOCAL_OBS_FILE}"
    python3 $MAIN_DIR/convert_to_little_r.py "$LOCAL_OBS_FILE" "$STATION_FILE" "${OBSPROC_DIR}/obs.${YYYY}${MM}${DD}${HH}"
    echo "Conversion to little_r format complete: ${OBSPROC_DIR}/obs.${YYYY}${MM}${DD}${HH}"
    cd $OBSPROC_DIR
    time mpirun --bind-to none -np 1 $WRFDA_DIR/var/obsproc/obsproc.exe
    
    # Check if obsproc output file was created successfully
    if [ -f "obs_gts_${YYYY}-${MM}-${DD}_${HH}:00:00.3DVAR" ]; then
        mv obs_gts_${YYYY}-${MM}-${DD}_${HH}:00:00.3DVAR $DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}/ob.ascii
        export OB_FORMAT=2
        echo "2" > $DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}/ob_format.txt
        echo "Successfully processed local observations with obsproc"
    else
        echo "WARNING: obsproc did not generate expected output file"
        echo "Expected file: obs_gts_${YYYY}-${MM}-${DD}_${HH}:00:00.3DVAR"
        export OB_FORMAT=1
        echo "1" > $DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}/ob_format.txt
    fi
else
    echo "No local observations file found. Using only NCEP observations."
    echo "Local observations file: $LOCAL_OBS_FILE"
    export OB_FORMAT=1
    echo "1" > $DA_DIR/ob/wrf_obs/${YYYY}${MM}${DD}${HH}/ob_format.txt
fi