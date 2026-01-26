#!/bin/bash 

# ===============================================
# WRF Preprocessing System (WPS) Automation Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

# Load the environment setup script
source /home/wrf/WRF_Model/scripts/env.sh

# Parse input arguments
year=$1
month=$2
day=$3
hour=$4
leadtime=$5

# Set boundary source (can be overridden by command line argument)
BOUNDARY_SOURCE=${6:-${BOUNDARY_SOURCE:-GFS}}

echo "============================================="
echo "WPS Configuration"
echo "============================================="
echo "Boundary Source: $BOUNDARY_SOURCE"
echo "Start Date: ${year}-${month}-${day} ${hour}:00:00"
echo "Lead Time: ${leadtime} hours"
echo "============================================="

# Set data directory and prefix based on boundary source
case "${BOUNDARY_SOURCE^^}" in
    GFS)
        DATA_DIR=$DATA_DIR_GFS
        UNGRIB_PREFIX="GFS"
        VTABLE="Vtable.GFS"
        GRIB_PATTERN="gfs*"
        ;;
    ECMWF)
        DATA_DIR=$DATA_DIR_ECMWF
        UNGRIB_PREFIX="ECMWF"
        VTABLE="Vtable.ECMWF"
        GRIB_PATTERN="*.grib2"
        ;;
    *)
        echo "Error: Unknown BOUNDARY_SOURCE '$BOUNDARY_SOURCE'. Must be GFS or ECMWF."
        exit 1
        ;;
esac

run_dir="${PROD_DIR}/${year}${month}${day}${hour}"  # Run directory

# Calculate start and end dates for the simulation
s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")

# Create the run directory
mkdir -p $run_dir
cd $run_dir
echo "Run directory created: $run_dir"

# ===============================================
# Read domain settings from domain.txt
# ===============================================
DOMAIN_FILE="${MAIN_DIR}/domain.txt"

if [ ! -f "$DOMAIN_FILE" ]; then
  echo "Error: domain.txt not found at $DOMAIN_FILE"
  echo "Please save your WRF Domain Wizard namelist.wps file as domain.txt in the scripts directory"
  exit 1
fi

echo "Reading domain configuration from $DOMAIN_FILE"

# Parse the domain.txt file using Python script
eval $(${MAIN_DIR}/parse_namelist_wps.py $DOMAIN_FILE)

# Generate the `namelist.wps` configuration file
# Build geogrid section dynamically based on projection type
GEOGRID_SECTION="&geogrid
 parent_id         = ${PARENT_ID[@]}
 parent_grid_ratio = ${PARENT_GRID_RATIO[@]}
 i_parent_start    = ${I_PARENT_START[@]}
 j_parent_start    = ${J_PARENT_START[@]}
 e_we              = ${E_WE[@]}
 e_sn              = ${E_SN[@]}
 geog_data_res     = 'modis_lakes+modis_30s+5m','modis_lakes+modis_30s+30s'
 dx                = $DX
 dy                = $DY
 map_proj          = '${MAP_PROJ}'
 ref_lat           = ${REF_LAT}
 ref_lon           = ${REF_LON}"

# Add projection-specific parameters
case "${MAP_PROJ,,}" in
    *lambert*)
        GEOGRID_SECTION="${GEOGRID_SECTION}
 truelat1          = ${TRUELAT1}
 truelat2          = ${TRUELAT2}
 stand_lon         = ${STAND_LON}"
        ;;
    *mercator*)
        GEOGRID_SECTION="${GEOGRID_SECTION}
 truelat1          = ${TRUELAT1}"
        ;;
    *lat-lon*|*latlon*|*cylindrical*)
        GEOGRID_SECTION="${GEOGRID_SECTION}
 stand_lon         = ${STAND_LON}"
        ;;
    *)
        echo "Warning: Unknown map projection '${MAP_PROJ}', using generic settings"
        # Include all available parameters
        [ -n "$TRUELAT1" ] && GEOGRID_SECTION="${GEOGRID_SECTION}
 truelat1          = ${TRUELAT1}"
        [ -n "$TRUELAT2" ] && GEOGRID_SECTION="${GEOGRID_SECTION}
 truelat2          = ${TRUELAT2}"
        [ -n "$STAND_LON" ] && GEOGRID_SECTION="${GEOGRID_SECTION}
 stand_lon         = ${STAND_LON}"
        ;;
esac

# Add pole_lat and pole_lon (used by all projections)
GEOGRID_SECTION="${GEOGRID_SECTION}
 pole_lat          = ${POLE_LAT}
 pole_lon          = ${POLE_LON}
 geog_data_path    = '${BASE_DIR}/WPS_GEOG/'
 opt_geogrid_tbl_path = '${WPS_DIR}/geogrid/'
/"

cat << EOF > namelist.wps
&share
 wrf_core                   = 'ARW'
 max_dom                    = 2
 start_date                 = '${year}-${month}-${day}_${hour}:00:00','${year}-${month}-${day}_${hour}:00:00'
 end_date                   = '${eyear}-${emonth}-${eday}_${ehour}:00:00','${eyear}-${emonth}-${eday}_${ehour}:00:00'
 active_grid                = .true., .true.
 interval_seconds           = 10800
 io_form_geogrid            = 2
/
${GEOGRID_SECTION}
&ungrib
 out_format                 = 'WPS'
 prefix                     = '${UNGRIB_PREFIX}'
/
&metgrid
 fg_name                    = '${UNGRIB_PREFIX}'
 io_form_metgrid            = 2
 opt_metgrid_tbl_path       = '${WPS_DIR}/metgrid/'
/
EOF
echo "Generated namelist.wps with boundary source: $BOUNDARY_SOURCE"

# ===============================================
# Step 1: Run Geogrid
# ===============================================
Vtable_dir="${WPS_DIR}/ungrib/Variable_Tables"
ln -sf ${Vtable_dir}/${VTABLE} Vtable
echo "Linked Vtable: ${VTABLE}"

cat << EOF > run_geogrid.bash
#!/bin/bash
cd ${run_dir}
time mpirun --bind-to none -np $((MAX_CPU < 10 ? MAX_CPU : 10)) ${WPS_DIR}/geogrid.exe
EOF

chmod +x run_geogrid.bash
./run_geogrid.bash

# check `geo_em.d02.nc` to confirm completion
if [ -f $run_dir/geo_em.d02.nc ]; then
  echo "Geogrid execution completed."
else
  echo "Error: Geogrid execution failed. Check logs."
  exit 1
fi

# ===============================================
# Step 2: Link Grib Files
# ===============================================
echo "Linking GRIB files from ${DATA_DIR}/${year}${month}${day}${hour}/${GRIB_PATTERN}"
${WPS_DIR}/link_grib.csh ${DATA_DIR}/${year}${month}${day}${hour}/${GRIB_PATTERN}
echo "GRIB files linked."

# ===============================================
# Step 3: Run Ungrib
# ===============================================
cat << EOF > run_ungrib.bash
#!/bin/bash
cd ${run_dir}
time mpirun --bind-to none -np 1 ${WPS_DIR}/ungrib.exe
EOF

chmod +x run_ungrib.bash
./run_ungrib.bash

# Check for the final ungrib file
if [ -f $run_dir/"${UNGRIB_PREFIX}:${eyear}-${emonth}-${eday}_${ehour}" ]; then
  echo "Ungrib execution completed."
else
  echo "Error: Ungrib execution failed. Check logs."
  exit 1
fi


# ===============================================
# Step 4: Run Metgrid
# ===============================================

cat << EOF > run_metgrid.bash
#!/bin/bash
cd ${run_dir}
time mpirun --bind-to none -np $((MAX_CPU < 20 ? MAX_CPU : 20)) ${WPS_DIR}/metgrid.exe
EOF

chmod +x run_metgrid.bash
./run_metgrid.bash

# Check for metgrid completion
if [ -f $run_dir/met_em.d02.${eyear}-${emonth}-${eday}_${hour}:00:00.nc ]; then
  echo "Metgrid execution completed."
else
  echo "Error: Metgrid execution failed. Check logs."
  exit 1
fi

echo "WPS preprocessing completed successfully!"

