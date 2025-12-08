#!/bin/bash

# ===============================================
# WRFDA (WRF Data Assimilation) script
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# Script inputs
year=$1; month=$2; day=$3; hour=$4; leadtime=$5; prod_dir=$6

# Directories and paths
run_dir="${PROD_DIR}/${year}${month}${day}${hour}"
s_date="$year-$month-$day ${hour}:00:00"

# ===============================================
# Read domain settings from domain.txt
# ===============================================
DOMAIN_FILE="${MAIN_DIR}/domain.txt"

if [ ! -f "$DOMAIN_FILE" ]; then
  echo "Error: domain.txt not found at $DOMAIN_FILE"
  echo "Please save your WRF Domain Wizard namelist.wps file as domain.txt in the scripts directory"
  exit 1
fi

echo "Reading domain configuration from $DOMAIN_FILE for WRFDA"

# Parse the domain.txt file using Python script for domain 1 (outer domain)
eval $(${MAIN_DIR}/parse_namelist_wps.py $DOMAIN_FILE 0)

# ===============================================
# Step 1: Prepare input files and working directory
# ===============================================

mkdir -p $DA_DIR/rc/
cp $run_dir/wrfinput_d* $DA_DIR/rc/
cp $run_dir/wrfbdy_d01 $DA_DIR/rc/
export WORK_DIR_DA=$run_dir/da_wrk
mkdir -p $WORK_DIR_DA
cd $WORK_DIR_DA
ln -sf $WRFDA_DIR/run/LANDUSE.TBL .
ln -sf $WRFDA_DIR/var/run/radiance_info ./radiance_info
ln -sf $WRFDA_DIR/var/run/leapsec.dat .
ln -sf $CRTM_COEFFS_PATH ./crtm_coeffs
ln -sf $CRTM_COEFFS_PATH $WRFDA_DIR/var/run/
ln -sf $DA_DIR/ob/{ob,airs,amsua,atms,gpsro,hirs3,hirs4,iasi,mhs,seviri,ssmis}.bufr $DA_DIR/be/be.dat $WRFDA_DIR/var/da/da_wrfvar.exe .

# ===============================================
# Step 2: Link VARBC and first guess files
# ===============================================

# Link VARBC file from previous cycle if exists.
[[ -f "$DA_DIR/varbc/VARBC.out" ]] && ln -sf $DA_DIR/varbc/VARBC.out ./VARBC.in || ln -sf $WRFDA_DIR/var/run/VARBC.in ./VARBC.in

# Check `fg` files from previous cycle
echo "Looking fg file wrfout_d01_${year}-${month}-${day}_${hour}:00:00"
if [[ -f "$DA_DIR/rc/wrfout_d01_${year}-${month}-${day}_${hour}:00:00" ]]; then
  echo "Found fg file, using warmstart"
  ln -sf $DA_DIR/rc/wrfout_d01_${year}-${month}-${day}_${hour}:00:00 ./fg
  ln -sf $DA_DIR/rc/wrfout_d02_${year}-${month}-${day}_${hour}:00:00 ./fg_d02
else
  echo "No fg file, using cold start..."
  ln -sf $DA_DIR/rc/wrfinput_d01 ./fg
  ln -sf $DA_DIR/rc/wrfinput_d02 ./fg_d02
fi

# ===============================================
# Step 3: Update lower boundary conditions
# ===============================================

echo "Updating lower boundary conditions..."
cp -p $DA_DIR/rc/wrfinput_d0* .
ln -sf $WRFDA_DIR/var/da/da_update_bc.exe .

for domain_id in 1 2; do
  fg_file="fg"
  [ $domain_id -eq 2 ] && fg_file="fg_d02"
  cat << EOF > parame.in
&control_param
  da_file            = '${WORK_DIR_DA}/${fg_file}',
  wrf_input          = '${WORK_DIR_DA}/wrfinput_d0${domain_id}',
  wrf_bdy_file	     = '${WORK_DIR_DA}/wrfbdy_d0${domain_id}',
  domain_id          = ${domain_id},
  cycling	           = .true.,
  update_low_bdy     = .true.,
  update_lateral_bdy = .false.,
  update_lsm 	       = .true.,
  debug		           = .true.,
  iswater   	       = 17,
  var4d_lbc          = .false.
/
EOF
  time mpirun -np 1 ./da_update_bc.exe
done

# Link updated input files to run directory
ln -sf $WORK_DIR_DA/wrfinput_d0{1,2} $run_dir/
echo "Lower boundary conditions updated."

# ===============================================
# Step 4: Configure WRFDA namelist
# ===============================================

# Check which observation files are available and non-empty
echo "Checking available observation files..."
use_amsua=".false."
use_mhs=".false."
use_atms=".false."
use_iasi=".false."
use_ssmis=".false."
use_airs=".false."
use_hirs3=".false."
use_hirs4=".false."
use_seviri=".false."

# Arrays to store sensor configurations
sensor_platforms=()
sensor_satids=()
sensor_ids=()

# Check AMSU-A
if [ -f "$DA_DIR/ob/amsua.bufr" ] && [ -s "$DA_DIR/ob/amsua.bufr" ]; then
    use_amsua=".true."
    # NOAA-15, 16, 18, 19 AMSU-A
    sensor_platforms+=(1 1 1 1)
    sensor_satids+=(15 16 18 19)
    sensor_ids+=(3 3 3 3)
    echo "  ✓ AMSU-A data available"
else
    echo "  ✗ AMSU-A data not available or empty"
fi

# Check MHS
if [ -f "$DA_DIR/ob/mhs.bufr" ] && [ -s "$DA_DIR/ob/mhs.bufr" ]; then
    use_mhs=".true."
    # NOAA-18, 19 MHS
    sensor_platforms+=(1 1)
    sensor_satids+=(18 19)
    sensor_ids+=(15 15)
    echo "  ✓ MHS data available"
else
    echo "  ✗ MHS data not available or empty"
fi

# Check ATMS
if [ -f "$DA_DIR/ob/atms.bufr" ] && [ -s "$DA_DIR/ob/atms.bufr" ]; then
    use_atms=".true."
    # Suomi-NPP ATMS
    sensor_platforms+=(17)
    sensor_satids+=(0)
    sensor_ids+=(19)
    echo "  ✓ ATMS data available"
else
    echo "  ✗ ATMS data not available or empty"
fi

# Check IASI
if [ -f "$DA_DIR/ob/iasi.bufr" ] && [ -s "$DA_DIR/ob/iasi.bufr" ]; then
    use_iasi=".true."
    # METOP-A IASI
    sensor_platforms+=(10)
    sensor_satids+=(2)
    sensor_ids+=(16)
    echo "  ✓ IASI data available"
else
    echo "  ✗ IASI data not available or empty"
fi

# Check SSMIS
if [ -f "$DA_DIR/ob/ssmis.bufr" ] && [ -s "$DA_DIR/ob/ssmis.bufr" ]; then
    use_ssmis=".true."
    # DMSP-16 SSMIS
    sensor_platforms+=(2)
    sensor_satids+=(16)
    sensor_ids+=(10)
    echo "  ✓ SSMIS data available"
else
    echo "  ✗ SSMIS data not available or empty"
fi

# Check AIRS
if [ -f "$DA_DIR/ob/airs.bufr" ] && [ -s "$DA_DIR/ob/airs.bufr" ]; then
    use_airs=".true."
    # EOS-Aqua AIRS
    sensor_platforms+=(9)
    sensor_satids+=(2)
    sensor_ids+=(11)
    echo "  ✓ AIRS data available"
else
    echo "  ✗ AIRS data not available or empty"
fi

# Check HIRS-3
if [ -f "$DA_DIR/ob/hirs3.bufr" ] && [ -s "$DA_DIR/ob/hirs3.bufr" ]; then
    use_hirs3=".true."
    # NOAA-15, 16, 17 HIRS-3
    sensor_platforms+=(1 1 1)
    sensor_satids+=(15 16 17)
    sensor_ids+=(0 0 0)
    echo "  ✓ HIRS-3 data available"
else
    echo "  ✗ HIRS-3 data not available or empty"
fi

# Check HIRS-4
if [ -f "$DA_DIR/ob/hirs4.bufr" ] && [ -s "$DA_DIR/ob/hirs4.bufr" ]; then
    use_hirs4=".true."
    # NOAA-18, 19 and METOP-A HIRS-4
    sensor_platforms+=(1 1 10)
    sensor_satids+=(18 19 2)
    sensor_ids+=(0 0 0)
    echo "  ✓ HIRS-4 data available"
else
    echo "  ✗ HIRS-4 data not available or empty"
fi

# Check SEVIRI
if [ -f "$DA_DIR/ob/seviri.bufr" ] && [ -s "$DA_DIR/ob/seviri.bufr" ]; then
    use_seviri=".true."
    # Meteosat-8 SEVIRI
    sensor_platforms+=(12)
    sensor_satids+=(1)
    sensor_ids+=(21)
    echo "  ✓ SEVIRI data available"
else
    echo "  ✗ SEVIRI data not available or empty"
fi

# Calculate total number of sensors
num_sensors=${#sensor_platforms[@]}
echo "Total sensors configured: $num_sensors"

# Build comma-separated lists for namelist
platform_list=$(IFS=,; echo "${sensor_platforms[*]}")
satid_list=$(IFS=,; echo "${sensor_satids[*]}")
sensor_list=$(IFS=,; echo "${sensor_ids[*]}")

# Set observation window
window=1
ob_window_min=$(date -d "$s_date $window hours ago" "+%Y-%m-%d %H:%M:%S")
ob_window_max=$(date -d "$s_date $window hours" "+%Y-%m-%d %H:%M:%S")

read minyear minmonth minday minhour minmin minsec <<< $(echo $ob_window_min | tr '-' ' ' | tr ':' ' ')
read maxyear maxmonth maxday maxhour maxmin maxsec <<< $(echo $ob_window_max | tr '-' ' ' | tr ':' ' ')

# Generate WRFDA namelist
cat << EOF > namelist.input
&wrfvar1
var4d                = false,
print_detail_grad    = false,
/
&wrfvar2
/
&wrfvar3
ob_format            = ${OB_FORMAT},
ob_format_gpsro      = 1,
num_fgat_time        = 1,
/
&wrfvar4
use_amsuaobs         = ${use_amsua}
use_amsubobs         = .false.
use_hirs3obs         = ${use_hirs3}
use_hirs4obs         = ${use_hirs4}
use_mhsobs           = ${use_mhs}
use_eos_amsuaobs     = .false.
use_ssmisobs         = ${use_ssmis}
use_atmsobs          = ${use_atms}
use_iasiobs          = ${use_iasi}
use_seviriobs        = ${use_seviri}
use_airsobs          = ${use_airs}
/
&wrfvar5
put_rand_seed        = true,
/
&wrfvar6
max_ext_its          = 1,
ntmax                = 200,
eps                  = 0.01,
orthonorm_gradient   = true,
/
&wrfvar7
cv_options           = 3,
/
&wrfvar8
/
&wrfvar9
/
&wrfvar10
test_transforms      = false,
test_gradient        = false,
/
&wrfvar11
/
&wrfvar12
/
&wrfvar13
/
&wrfvar14
rtminit_nsensor      = ${num_sensors},
rtminit_platform     = ${platform_list},
rtminit_satid        = ${satid_list},
rtminit_sensor       = ${sensor_list},
qc_rad               = true,
write_iv_rad_ascii   = false,
write_oa_rad_ascii   = true,
rtm_option           = 2,
only_sea_rad         = false,
use_varbc            = true,
use_crtm_kmatrix     = true,
crtm_coef_path       = "${BASE_DIR}/CRTM_coef/crtm_coeffs_2.3.0",
crtm_irland_coef     = 'IGBP.IRland.EmisCoeff.bin',
thinning_mesh        = 60.0,
thinning             = true,
airs_warmest_fov     = true,
/
&wrfvar15
/
&wrfvar16
/
&wrfvar17
/
&wrfvar18
analysis_date        = "${year}-${month}-${day}_${hour}:00:00.0000",
/
&wrfvar19
/
&wrfvar20
/
&wrfvar21
time_window_min      = "${minyear}-${minmonth}-${minday}_${minhour}:00:00.0000",
/
&wrfvar22
time_window_max      = "${maxyear}-${maxmonth}-${maxday}_${maxhour}:00:00.0000",
/
&time_control
start_year           = ${year},
start_month          = ${month},
start_day            = ${day},
start_hour           = ${hour},
end_year             = ${year},
end_month            = ${month},
end_day              = ${day},
end_hour             = ${hour},
/
&fdda
grid_fdda                  = 0
/
&domains
time_step            = 60,
e_we                 = ${E_WE[0]},
e_sn                 = ${E_SN[0]},
e_vert               = 45,
dx                   = ${DX},
dy                   = ${DY}, 
/
&dfi_control
/
&tc
/
&physics
mp_physics                 = 8, 
mp_zero_out                = 0,
mp_zero_out_thresh         = 1.e-8
mp_tend_lim                = 10.
no_mp_heating              = 0,
do_radar_ref               = 1,
shcu_physics               = 0,
topo_wind                  = 0,
isfflx                     = 1,
iz0tlnd                    = 1,
isftcflx                   = 0,
ra_lw_physics              = 4,   
ra_sw_physics              = 4,  
radt                       = 10,
sf_sfclay_physics          = 1,
sf_surface_physics         = 2,
bl_pbl_physics             = 1,
bldt                       = 0,
cu_physics                 = 1,
cudt                       = 5,
ifsnow                     = 1,
icloud                     = 1,
surface_input_source       = 3,
num_soil_layers            = 4,
num_land_cat               = 21,
sf_urban_physics           = 0,
sst_update                 = 1,
tmn_update                 = 1,
sst_skin                   = 1,
kfeta_trigger              = 1,
mfshconv                   = 0,
prec_acc_dt                = 0,
sf_lake_physics            = 1,
/
&scm
/
&dynamics
diff_opt                   = 2,
km_opt                     = 4,
/
&bdy_control
spec_bdy_width             = 10
spec_zone                  = 1
relax_zone                 = 9
spec_exp                   = 0.33,
specified                  = T,
nested                     = F,
/
&grib2
/
&fire
/
&namelist_quilt
nio_tasks_per_group        = 0
nio_groups                 = 1
/
&perturbation
/
&radar_da
/
EOF

# ===============================================
# Step 5: Run data assimilation
# ===============================================

echo "Running da_wrfvar.exe..."
time mpirun -np $((MAX_CPU < 20 ? MAX_CPU : 20)) ${WORK_DIR_DA}/da_wrfvar.exe
echo "DA completed."

# ===============================================
# Step 6: Update lateral boundary conditions
# ===============================================

echo "Updating lateral boundary conditions..."
cd $WORK_DIR_DA
cp -p $DA_DIR/rc/wrfbdy_d01 .
cat << EOF > parame.in
&control_param
da_file            = '${WORK_DIR_DA}/wrfvar_output'
wrf_bdy_file       = '${WORK_DIR_DA}/wrfbdy_d01'
wrf_input	         = '${WORK_DIR_DA}/wrfinput_d01'
domain_id          = 1
cycling		         = .true.
debug   	         = .true.
update_lateral_bdy = .true.
update_low_bdy 	   = .false.
update_lsm 	       = .true.
iswater   	       = 17
var4d_lbc 	       = .false.
/
EOF
time mpirun -np 1 ./da_update_bc.exe
echo "Lateral boundary conditions updated."

# ===============================================
# Step 7: Link DA output files for WRF run
# ===============================================
echo "Linking DA output files to run directory..."
ln -sf $WORK_DIR_DA/wrfvar_output $run_dir/wrfinput_d01
ln -sf $WORK_DIR_DA/wrfbdy_d01 $run_dir/wrfbdy_d01
echo "WRFDA cycle completed successfully."
