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

# Base URL
BASE_URL="https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/gdas.${YYYY}${MM}${DD}/"

# Files to download
FILES=(
    "gdas.t${HH}z.1bamua.tm00.bufr_d"
    "gdas.t${HH}z.1bhrs4.tm00.bufr_d"
    "gdas.t${HH}z.1bmhs.tm00.bufr_d"
    "gdas.t${HH}z.airsev.tm00.bufr_d"
    "gdas.t${HH}z.atms.tm00.bufr_d"
    "gdas.t${HH}z.mtiasi.tm00.bufr_d"
    "gdas.t${HH}z.gpsro.tm00.bufr_d.nr"
    "gdas.t${HH}z.prepbufr.nr"
)
# Create necessary directories with full path checking
echo "Creating necessary directories..."
for dir in "$DA_DIR/ob" "$DA_DIR/ob/raw_obs" "$DA_DIR/ob/obsproc"; do
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "$dir" || { echo "ERROR: Failed to create directory $dir"; exit 1; }
    fi
done

# Also create needed verification directories
mkdir -p "${BASE_DIR}/Verification/Data/Obs" || { echo "ERROR: Failed to create directory ${BASE_DIR}/Verification/Data/Obs"; exit 1; }

# Download the files
cd "$DA_DIR/ob" || { echo "ERROR: Failed to change to directory $DA_DIR/ob"; exit 1; }
for FILE in "${FILES[@]}"; do
    URL="${BASE_URL}${FILE}"
    echo "Downloading ${FILE}..."
    curl -O "${URL}"
done

mv gdas.t${HH}z.1bamua.tm00.bufr_d amsua.bufr
mv gdas.t${HH}z.1bhrs4.tm00.bufr_d hirs4.bufr
mv gdas.t${HH}z.1bmhs.tm00.bufr_d mhs.bufr
mv gdas.t${HH}z.airsev.tm00.bufr_d airs.bufr
mv gdas.t${HH}z.atms.tm00.bufr_d atms.bufr
mv gdas.t${HH}z.mtiasi.tm00.bufr_d iasi.bufr
mv gdas.t${HH}z.gpsro.tm00.bufr_d.nr gpsro.bufr
mv gdas.t${HH}z.prepbufr.nr ob.bufr


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

cat << EOF > namelist.obsproc
&record1
 obs_gts_filename = 'obs.${YYYY}${MM}${DD}${HH}',
 obs_err_filename = 'obserr.txt',
 gts_from_mmm_archive = .true.,
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
 IPROJ = 3,
 PHIC  = 40.00001,
 XLONC = -95.0,
 TRUELAT1= 30.0,
 TRUELAT2= 60.0,
 MOAD_CEN_LAT = 40.00001,
 STANDARD_LON = -95.00,
/

&record8
 IDD    =   1,
 MAXNES =   1,
 NESTIX =  60,  200,
 NESTJX =  90,  200,
 DIS    =  60,  10.,
 NUMC   =    1,    1,
 NESTI  =    1,   40,
 NESTJ  =    1,   60,
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
COUNTRY_SCRIPT="$MAIN_DIR/process_local_obs/process_local_obs_${COUNTRY}.sh"

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
LOCAL_OBS_FILE="${DA_DIR}/ob/raw_obs/${YYYY}${MM}${DD}${HH}_local_obs.csv"
STATION_FILE="${DA_DIR}/ob/raw_obs/station_file.csv"

#Run obsproc if local observations file exists
if [ -f "$LOCAL_OBS_FILE" ]; then
    echo "Local observations file found: ${LOCAL_OBS_FILE}"
    python3 $MAIN_DIR/convert_to_little_r.py "$LOCAL_OBS_FILE" "$STATION_FILE" "${OBSPROC_DIR}/obs.${YYYY}${MM}${DD}${HH}"
    echo "Conversion to little_r format complete: ${OBSPROC_DIR}/obs.${YYYY}${MM}${DD}${HH}"
    cd $OBSPROC_DIR
    time mpirun -np 1 $WRFDA_DIR/var/obsproc/obsproc.exe
    mv obs_gts_${YYYY}-${MM}-${DD}_${HH}:00:00.3DVAR $DA_DIR/ob/ob.ascii
    export OB_FORMAT=2
else
    echo "No local observations file found. Using only NCEP observations."
    export OB_FORMAT=1
fi