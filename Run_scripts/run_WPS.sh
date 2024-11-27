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
prod_dir=$6

# Configuration variables
interval=3                                          # Interval in hours
res="0p025"                                         # Data resolution
data_dir="/home/wrf/WRF_Model/GFS/"         # GFS data directory
wps_dir="/home/wrf/WRF_Model/WPS/"          # WPS directory
run_dir="${prod_dir}/${year}${month}${day}${hour}"  # Run directory

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
 i_parent_start    = 1,21,
 j_parent_start    = 1,18,
 e_we              = 103,286,
 e_sn              = 195,186,
 geog_data_res     = 'modis_lakes+modis_30s+5m','modis_lakes+modis_30s+30s',
 dx                = 7000,
 dy                = 7000,
 map_proj          = 'lambert',
 ref_lat           = 64.321,
 ref_lon           = 25.539,
 truelat1          = 65.740,
 truelat2          = 65.740,
 pole_lat          = 90,
 pole_lon          = 0,
 stand_lon         = 24.873,
 geog_data_path    = '/home/wrf/WRF_Model/WPS_GEOG/',
 opt_geogrid_tbl_path = '/home/wrf/WRF_Model/WPS/geogrid/',
/
&ungrib
 out_format                 = 'WPS'
 prefix                     = 'GFS'
/
&metgrid
 fg_name                    = 'GFS'
 io_form_metgrid            = 2
 opt_metgrid_tbl_path       = '/home/wrf/WRF_Model/WPS/metgrid/'
/
EOF
echo "Generated namelist.wps"

# ===============================================
# Step 1: Run Geogrid
# ===============================================
Vtable_dir="/home/wrf/WRF_Model/WPS/ungrib/Variable_Tables"
ln -sf ${Vtable_dir}/Vtable.GFS Vtable
echo "link Vtable finish"

cat << EOF > run_geogrid.bash
#!/bin/bash
cd ${run_dir}
time mpirun -np 1 ${wps_dir}geogrid.exe
EOF

chmod +x run_geogrid.bash
./run_geogrid.bash

# Wait for `geo_em.d02.nc` to confirm completion
until [ -f geo_em.d02.nc ]; do
  echo "Waiting for geogrid to complete..."
  sleep 5
done
echo "Geogrid execution completed."

# ===============================================
# Step 2: Link Grib Files
# ===============================================
${wps_dir}/link_grib.csh ${data_dir}/${year}${month}${day}${hour}/gfs*
echo "Grib files linked."

# ===============================================
# Step 3: Run Ungrib
# ===============================================
cat << EOF > run_ungrib.bash
#!/bin/bash
cd ${run_dir}
time mpirun -np 1 ${wps_dir}ungrib.exe
EOF

chmod +x run_ungrib.bash
./run_ungrib.bash

# Wait for the final ungrib file
until [ -f "GFS:${eyear}-${emonth}-${eday}_${ehour}" ]; do
  echo "Waiting for ungrib to complete..."
  sleep 5
done
echo "Ungrib execution completed."

# ===============================================
# Step 4: Run Metgrid
# ===============================================

cat << EOF > run_metgrid.bash
#!/bin/bash
cd ${run_dir}
time mpirun -np 24 ${wps_dir}metgrid.exe
EOF

chmod +x run_metgrid.bash
./run_metgrid.bash

# Wait for metgrid completion
until [ -f met_em.d02.${eyear}-${emonth}-${eday}_${hour}:00:00.nc ]; do
  echo "Waiting for METGRID to complete..."
  sleep 60
done
echo "Metgrid execution completed."

# Final validation
if [ -f ${run_dir}/met_em.d02.${eyear}-${emonth}-${eday}_${hour}:00:00.nc ]; then
  echo "WPS preprocessing completed successfully!"
else
  echo "Error: WPS preprocessing failed. Check logs."
  exit 1
fi
