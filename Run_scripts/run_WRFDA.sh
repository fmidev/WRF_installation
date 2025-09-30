#!/bin/bash

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

year=$1; month=$2; day=$3; hour=$4; leadtime=$5; prod_dir=$6

# Directories and paths
run_dir="${PROD_DIR}/${year}${month}${day}${hour}"
s_date="$year-$month-$day ${hour}:00:00"

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
ln -sf $DA_DIR/ob/{ob,airs,amsua,atms,gpsro,hirs4,iasi,mhs}.bufr $DA_DIR/be/be.dat $WRFDA_DIR/var/da/da_wrfvar.exe .

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

# Update lower boundary conditions
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

# Link updated input files
ln -sf $WORK_DIR_DA/wrfinput_d0{1,2} $run_dir/

# Set observation window
window=1
ob_window_min=$(date -d "$s_date $window hours ago" "+%Y-%m-%d %H:%M:%S")
ob_window_max=$(date -d "$s_date $window hours" "+%Y-%m-%d %H:%M:%S")

read minyear minmonth minday minhour minmin minsec <<< $(echo $ob_window_min | tr '-' ' ' | tr ':' ' ')
read maxyear maxmonth maxday maxhour maxmin maxsec <<< $(echo $ob_window_max | tr '-' ' ' | tr ':' ' ')

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
/
&wrfvar4
use_amsuaobs         = .true.
use_amsubobs         = .false.
use_hirs3obs         = .false.
use_hirs4obs         = .true.
use_mhsobs           = .true.
use_eos_amsuaobs     = .false.
use_ssmisobs         = .false.
use_atmsobs          = .true.
use_iasiobs          = .true.
use_seviriobs        = .false.
use_airsobs          = .true.
/
&wrfvar5
/
&wrfvar6
max_ext_its          = 1,
ntmax                = 50,
orthonorm_gradient   = true,
/
&wrfvar7
cv_options=3,
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
rtminit_nsensor=14,
rtminit_platform=9,10,1,1,1,1,1,1,10,1,1,17,10,9,
rtminit_satid=2,2,15,16,18,19,18,19,2,18,19,0,2,2,
rtminit_sensor=3,3,3,3,3,3,0,0,15,15,15,19,16,11,
qc_rad=true,
write_iv_rad_ascii=false,
write_oa_rad_ascii=true,
rtm_option=2,
only_sea_rad=false,
use_varbc=true,
crtm_coef_path="${BASE_DIR}/CRTM_coef/crtm_coeffs_2.3.0"
crtm_irland_coef='IGBP.IRland.EmisCoeff.bin' 
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
time_step            = 30,
e_we                 = 103,
e_sn                 = 195,
e_vert               = 45,
dx                   = 7000.0000,
dy                   = 7000.0000, 
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
sst_update                 = 0,
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
# Step 3: Run data assimilation
# ===============================================
echo "Running da_wrfvar.exe..."
time mpirun -np ${MAX_CPU} ${WORK_DIR_DA}/da_wrfvar.exe
echo "DA completed."

# Update lateral boundary conditions
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

# Link DA output files for WRF run
ln -sf $WORK_DIR_DA/wrfvar_output $run_dir/wrfinput_d01
ln -sf $WORK_DIR_DA/wrfbdy_d01 $run_dir/wrfbdy_d01
echo "Linked updated files"
