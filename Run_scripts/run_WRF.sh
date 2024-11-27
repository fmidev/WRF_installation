#!/bin/bash

# ===============================================
# WRF Model Automation Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

#Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# Script inputs
year=$1;month=$2;day=$3;hour=$4;leadtime=$5 prod_dir=$6
interval=6;

# Directories and paths
wps_dir="/home/wrf/WRF_Model/WPS"
wrf_dir="/home/wrf/WRF_Model/WRF"
run_dir="${prod_dir}/${year}${month}${day}${hour}"

# Calculate end date and time
s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")


# Check initial and boundary conditions
cd ${run_dir}
if [ -f ${run_dir}/met_em.d02.${eyear}-${emonth}-${eday}_${ehour}:00:00.nc ];then
  echo "Ready to set up WRF" 
else
  echo "Not enough ICBC files"
  exit 1
fi

# Link required files for WRF run
ln -sf ${wrf_dir}/main/*.exe .
ln -sf $wrf_dir/run/{gribmap.txt,RRTM*,*TBL,*tbl,ozone*,CAMtr*} .
echo "Linked necessary files"

# Configure `namelist.input` for WRF run
run_days=$((leadtime/24))
cat << EOF > namelist.input
&time_control
 run_days                   = ${run_days},
 run_hours                  = 0,
 run_minutes                = 0,
 run_seconds                = 0,
 start_year                 = $year, $year, 2017,
 start_month                = $month, $month,   01,
 start_day                  = $day, $day,   24,
 start_hour                 = $hour, $hour,   12,
 end_year                   = $eyear, $eyear, 2000,
 end_month                  = $emonth, $emonth,   01,
 end_day                    = $eday, $eday,   25,
 end_hour                   = $ehour, $ehour,   12,
 interval_seconds           = 10800
 input_from_file            = .true.,.true.,.true.,
 history_interval           = 60, 60,
 frames_per_outfile         = 1, 1,
 restart                    = .false.,
 restart_interval           = 14400,
 io_form_history            = 2
 io_form_auxinput4          = 2
 auxinput4_interval         = 360
 auxinput4_inname           = "wrflowinp_d<domain>"
 io_form_input              = 2
 io_form_restart            = 2
 io_form_boundary           = 2
 debug_level                = 0
 use_netcdf_classic         = T
 /

&domains
 time_step                  = 30
 time_step_fract_num        = 0
 time_step_fract_den        = 1
 time_step_dfi              = 15
 max_dom                    = 2
 s_we                       = 1, 1
 e_we                       = 103,286,                                                                                                                       
 e_sn                       = 195,186,
 s_vert                     = 1, 1
 e_vert                     = 45, 45
 num_metgrid_levels         = 34,
 num_metgrid_soil_levels    = 4,
 dx                         = 7000.0000, 1400.0000
 dy                         = 7000.0000, 1400.0000
 grid_id                    = 1, 2
 parent_id                  = 0, 1
 i_parent_start             = 1, 21,
 j_parent_start             = 1, 18,
 parent_grid_ratio          = 1, 5
 parent_time_step_ratio     = 1, 3
 feedback                   = 1
 smooth_option              = 0
 /


&physics
 mp_physics                 = 2,     2,     3,
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
 ra_lw_physics              = 1,     1,     1,
 ra_sw_physics              = 1,     1,     1,
 radt                       = 30,    30,    30,
 sf_sfclay_physics          = 1,     1,     1,
 sf_surface_physics         = 2,     2,     2,
 bl_pbl_physics             = 1,     1,     1,
 bldt                       = 0,     0,     0,
 cu_physics                 = 1,     1,     0,
 cudt                       = 5,     5,     5,
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
 use_lakedepth 		          = 0,
 /

&noah_mp
/

&dynamics
 hybrid_opt                 = 2,
 etac                       = 0.175,
 w_damping                  = 1,
 diff_opt                   = 1,      1,      1,
 km_opt                     = 4,      4,      4,
 diff_6th_opt               = 2,      2,      2,
 diff_6th_factor            = 0.12,   0.12,   0.12,
 base_temp                  = 290.
 damp_opt                   = 3,
 zdamp                      = 5000.,  5000.,  5000.,
 dampcoef                   = 0.2,    0.2,    0.2
 khdif                      = 0,      0,      0,
 kvdif                      = 0,      0,      0,
 non_hydrostatic            = .true., .true., .true.,
 moist_adv_opt              = 1,      1,      1,
 scalar_adv_opt             = 1,      1,      1,
 gwd_opt                    = 1,
/

&fdda
 grid_fdda                  = 0
/

&bdy_control
 spec_bdy_width             = 10
 spec_zone                  = 1
 relax_zone                 = 9
 spec_exp                   = 0.33,
 specified                  = T, F
 nested                     = F, T
/ob_window_min

&grib2
/

&namelist_quilt
 nio_tasks_per_group        = 0
 nio_groups                 = 1
/

&diags
 p_lev_diags                = 0
 z_lev_diags                = 0
/
EOF

# ===============================================
# Step 1: Run `real.exe` for initialization
# ===============================================

echo "Running real.exe..."
time mpirun -np 10 ${run_dir}/real.exe
echo "Real.exe completed."

# ===============================================
# Step 2: Data assimilation setup (optional, WRFDA variable true/false)
# ===============================================
if $WRFDA; then
  export WRFDA_DIR=/home/wrf/WRF_Model/WRFDA/
  export DAT_DIR=/home/wrf/WRF_Model/DA_input/
  crtm_coeffs_path=/home/wrf/WRF_Model/CRTM_coef/crtm_coeffs_2.3.0
  
  mkdir -p $DAT_DIR/rc/
  cp $run_dir/wrfinput_d* $DAT_DIR/rc/
  cp $run_dir/wrfbdy_d01 $DAT_DIR/rc/
  export WORK_DIR_DA=$run_dir/da_wrk
  mkdir -p $WORK_DIR_DA
  cd $WORK_DIR_DA
  ln -sf $WRFDA_DIR/run/LANDUSE.TBL .
  ln -sf $WRFDA_DIR/var/run/radiance_info ./radiance_info
  ln -sf $WRFDA_DIR/var/run/leapsec.dat .
  ln -sf $crtm_coeffs_path ./crtm_coeffs
  ln -sf $crtm_coeffs_path $WRFDA_DIR/var/run/
  ln -sf $DAT_DIR/ob/{ob,airs,amsua,atms,gpsro,hirs4,iasi,mhs}.bufr $DAT_DIR/be/be.dat $WRFDA_DIR/var/da/da_wrfvar.exe .

  if [[ -f "$DAT_DIR/varbc/VARBC.out" ]]; then
    ln -sf $DAT_DIR/varbc/VARBC.out ./VARBC.in
  else
    ln -sf $WRFDA_DIR/var/run/VARBC.in ./VARBC.in
  fi

  # Check `fg` files from previous cycle
  echo "Looking fg file wrfout_d01_${year}-${month}-${day}_${hour}:00:00"

  if [[ -f "$DAT_DIR/rc/wrfout_d01_${year}-${month}-${day}_${hour}:00:00" ]]; then
    echo "Found fg file, using warmstart"
    ln -sf $DAT_DIR/rc/wrfout_d01_${year}-${month}-${day}_${hour}:00:00 ./fg
    ln -sf $DAT_DIR/rc/wrfout_d02_${year}-${month}-${day}_${hour}:00:00 ./fg_d02
  else
    echo "No fg file, using cold start..." 
    ln -sf $DAT_DIR/rc/wrfinput_d01 ./fg
    ln -sf $DAT_DIR/rc/wrfinput_d02 ./fg_d02
  fi

  # Update lower boundary conditions
  cp -p $DAT_DIR/rc/wrfinput_d0* .
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
  ob_format            = 1,
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
  crtm_coef_path="${WRFDA_DIR}/var/run/crtm_coeffs_2.3.0"
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
  mp_physics                 = 2, 
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
  ra_lw_physics              = 1,   
  ra_sw_physics              = 1,  
  radt                       = 30,
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
  diff_opt                   = 1,
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
  time mpirun -np 20 ${WORK_DIR_DA}/da_wrfvar.exe
  echo "DA completed."

  # Update lateral boundary conditions
  cd $WORK_DIR_DA
  cp -p $DAT_DIR/rc/wrfbdy_d01 .
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
else
  echo "Running model without data assimilation"
fi
# ===============================================
# Step 4: Run WRF model
# ===============================================

echo "Ready to run WRF.exe"
cd $run_dir
time mpirun -np 40 ./wrf.exe
if [ ! -f "${run_dir}/wrfout_d02_${eyear}-${emonth}-${eday}_${ehour}:00:00" ]; then
  echo "Error: WRF failed."
  exit 1
fi
echo "WRF finished"

# ===============================================
# Step 5: Copy files for next cycle (wooth DA only)
# ===============================================
if $WRFDA; then
  echo "Copying fg and VARBC files"
  #First guess files
  fg_date=$(date -d "$s_date $interval hours" "+%Y-%m-%d %H:%M:%S")
  read fgyear fgmonth fgday fghour fgmin fgsec <<< $(echo $fg_date | tr '-' ' ' | tr ':' ' ')
  cp $run_dir/wrfout_d01_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00 $DAT_DIR/rc/ || :
  cp $run_dir/wrfout_d02_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00 $DAT_DIR/rc/ || :
  #VARBC file
  cp $WORK_DIR_DA/VARBC.out $DAT_DIR/varbc/ || :
fi

echo "Cycle" ${year}${month}${day}${hour}" WRF run finished"


