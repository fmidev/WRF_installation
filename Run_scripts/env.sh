#!/bin/bash 

# Base directory
export BASE_DIR=/home/wrf/WRF_Model

# Library paths
export OPENMPI=$BASE_DIR/libraries/openmpi-5.0.3/install/
export NETCDF=$BASE_DIR/libraries/netcdf-c-4.9.2/install/
export HDF5=$BASE_DIR/libraries/hdf5-1.14.4-3/install
export jasper=$BASE_DIR/libraries/jasper-1.900.1/install/
export JASPERLIB=$BASE_DIR/libraries/jasper-1.900.1/install/lib
export JASPERINC=$BASE_DIR/libraries/jasper-1.900.1/install/include
export ZLIB=$BASE_DIR/libraries/zlib-1.3.1/install/lib
export LD_LIBRARY_PATH="$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$ZLIB:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$ZLIB:$LIBRARY_PATH"
export PATH="$HOME/.local/bin:$HOME/bin:/home/wrf/WRF_Model/libraries/openmpi-5.0.3/install/bin:/home/wrf/WRF_Model/libraries/netcdf-c-4.9.2/install/bin:$PATH"

# Source code directories
export WPS_DIR=$BASE_DIR/WPS
export WRF_DIR=$BASE_DIR/WRF
export WRFDA_DIR=$BASE_DIR/WRFDA

# Variables
export NETCDF4=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export GRIBNUM=20 # Number of GFS GRIB files needed to be found
export LEADTIME=48 # Forecast lead time in hours
export INTERVAL=6 # Interval between the cycles in hours (needed for WRFDA)

# Paths to run directories
export DA_DIR=$BASE_DIR/DA_input/
export CRTM_COEFFS_PATH=$BASE_DIR/CRTM_coef/crtm_coeffs_2.3.0
export MAIN_DIR=$BASE_DIR/scripts
export PROD_DIR=$BASE_DIR/out
export DATA_DIR=$BASE_DIR/GFS
export VERIFICATION_DIR=$BASE_DIR/Verification/Scripts

# Switches for WRF model run steps
export RUN_CHECK_BOUNDARY_FILES=true
export RUN_GET_OBS=true
export RUN_WPS=true
export RUN_WRF=true
export WRFDA=false
export RUN_UPP=false
export RUN_VERIFICATION=false
export RUN_COPY_GRIB=false