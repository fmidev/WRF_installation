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

# Generate the `namelist.wps` configuration file
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
&geogrid
 parent_id         = 1,1,
 parent_grid_ratio = 1,5,
 i_parent_start    = 1,124,
 j_parent_start    = 1,87,
 e_we              = 324,376,
 e_sn              = 214,271,
 geog_data_res     = 'modis_lakes+modis_30s+5m','modis_lakes+modis_30s+30s',
 dx                = 10000,
 dy                = 10000,
 map_proj          = 'mercator',
 ref_lat           = 38.115,
 ref_lon           = 71.160,
 truelat1          = 38.331,
 pole_lat          = 90,
 pole_lon          = 0,
 geog_data_path    = '${BASE_DIR}/WPS_GEOG/',
 opt_geogrid_tbl_path = '${WPS_DIR}/geogrid/',
/
&ungrib
 out_format                 = 'WPS'
 prefix                     = 'GFS'
/
&metgrid
 fg_name                    = 'GFS'
 io_form_metgrid            = 2
 opt_metgrid_tbl_path       = '${WPS_DIR}/metgrid/'
/
EOF
echo "Generated namelist.wps"

# ===============================================
# Step 1: Run Geogrid
# ===============================================
Vtable_dir="${WPS_DIR}/ungrib/Variable_Tables"
ln -sf ${Vtable_dir}/Vtable.GFS Vtable
echo "link Vtable finish"

cat << EOF > run_geogrid.bash
#!/bin/bash
cd ${run_dir}
time mpirun -np 10 ${WPS_DIR}/geogrid.exe
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
${WPS_DIR}/link_grib.csh ${DATA_DIR}/${year}${month}${day}${hour}/gfs*
echo "Grib files linked."

# ===============================================
# Step 3: Run Ungrib
# ===============================================
cat << EOF > run_ungrib.bash
#!/bin/bash
cd ${run_dir}
time mpirun -np 1 ${WPS_DIR}/ungrib.exe
EOF

chmod +x run_ungrib.bash
./run_ungrib.bash

# Check for the final ungrib file
if [ -f $run_dir/"GFS:${eyear}-${emonth}-${eday}_${ehour}" ]; then
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
time mpirun -np ${MAX_CPU} ${WPS_DIR}/metgrid.exe
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

