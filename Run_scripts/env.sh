#!/bin/bash 

# Base directory
export BASE_DIR=/home/wrf/WRF_Model
export LIB_DIR=$BASE_DIR/libraries

# Library paths
export OPENMPI=$LIB_DIR/openmpi/install
export NETCDF=$LIB_DIR/netcdf-c/install
export HDF5=$LIB_DIR/hdf5/install
export jasper=$LIB_DIR/jasper/install
export JASPERLIB=$LIB_DIR/jasper/install/lib
export JASPERINC=$LIB_DIR/jasper/install/include
export ZLIB=$LIB_DIR/zlib/install/lib
export LD_LIBRARY_PATH="$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$ZLIB:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$ZLIB:$LIBRARY_PATH"
export PATH="$HOME/.local/bin:$HOME/bin:$OPENMPI/bin:$NETCDF/bin:$PATH"

# Source code directories
export WPS_DIR=$BASE_DIR/WPS
export WRF_DIR=$BASE_DIR/WRF
export WRFDA_DIR=$BASE_DIR/WRFDA

# Variables
export NETCDF4=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export GRIBNUM=25 # Number of GFS GRIB files needed to be found
export LEADTIME=72 # Forecast lead time in hours (if changing this, also change the lastfhr in the UPP_wrk/postprd/run_unipost)
export INTERVAL=6 # Interval between the cycles in hours (needed for WRFDA)
export MAX_CPU=20  # Number of CPU cores to use
export COUNTRY="" # Country for country-specific observation processing scripts
ulimit -s unlimited

# Paths to run directories
export DA_DIR=$BASE_DIR/DA_input
export CRTM_COEFFS_PATH=$BASE_DIR/CRTM_coef/crtm_coeffs_2.3.0
export MAIN_DIR=$BASE_DIR/scripts
export PROD_DIR=$BASE_DIR/out
export DATA_DIR=$BASE_DIR/GFS
export VERIFICATION_DIR=$BASE_DIR/Verification/scripts

# Switches for WRF model run steps
export RUN_CHECK_BOUNDARY_FILES=true
export RUN_GET_OBS=true
export RUN_WPS=true
export RUN_WRF=true
export RUN_WRFDA=true
export RUN_UPP=true
export RUN_VERIFICATION=true
export RUN_COPY_GRIB=true