#!/bin/bash 

# Base directory
export BASE_DIR=/home/wrf/WRF_Model

# Library paths
export OPENMPIF=$BASE_DIR/libraries/openmpi/4.1.4.1/fortran-gnu/
export OPENMPI=$BASE_DIR/libraries/openmpi/4.1.4.1/
export NETCDF=$BASE_DIR/libraries/netcdf-fortran/4.5.4/gcc-9.3.0/openmpi-4.1.4.1/
export NETCDFC=$BASE_DIR/libraries/netcdf-c/4.8.1/gcc-9.3.0/openmpi-4.1.4.1/
export HDF5=$BASE_DIR/libraries/hdf5/1.12.2/gcc-9.3.0/openmpi-4.1.4.1
export jasper=$BASE_DIR/libraries/asper-1.900.1/install/
export JASPERLIB=$BASE_DIR/libraries/jasper-1.900.1/install/lib
export JASPERINC=$BASE_DIR/libraries/jasper-1.900.1/install/include
export LD_LIBRARY_PATH="$NETCDFC/lib:$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$OPENMPIF/lib"
export LIBRARY_PATH="$NETCDFC/lib:$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$OPENMPIF/lib:$LIBRARY_PATH"

# Source code directories
export WPS_DIR=$BASE_DIR/WPS
export WRF_DIR=$BASE_DIR/WRF_Model/WRF
export WRFDA_DIR=$BASE_DIR/WRFDA

# Variables
export NETCDF4=1
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export GRIBNUM=20 # Number of GFS GRIB files needed to be found
export LEADTIME=48 # Forecast lead time in hours
export WRFDA=true # true|false
export INTERVAL=6; # Interval between the cycles in hours (needed for WRFDA)

# Paths to run directories
export DAT_DIR=$BASE_DIR/DA_input/
export CRTM_COEFFS_PATH=$BASE_DIR/CRTM_coef/crtm_coeffs_2.3.0
export MAIN_DIR=$BASE_DIR/scripts
export PROD_DIR=$BASE_DIR/out
export DATA_DIR=$BASE_DIR/GFS
export VERIFICATION_DIR=$BASE_DIR/Verification/Scripts
