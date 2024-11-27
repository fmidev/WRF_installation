#!/bin/bash 
export OPENMPIF=/home/wrf/WRF_Model/libraries/openmpi/4.1.4.1/fortran-gnu/
export OPENMPI=/home/wrf/WRF_Model/libraries/openmpi/4.1.4.1/
export NETCDF=/home/wrf/WRF_Model/libraries/netcdf-fortran/4.5.4/gcc-9.3.0/openmpi-4.1.4.1/
export NETCDFC=/home/wrf/WRF_Model/libraries/netcdf-c/4.8.1/gcc-9.3.0/openmpi-4.1.4.1/
export NETCDF4=1
export HDF5=/home/wrf/WRF_Model/libraries/hdf5/1.12.2/gcc-9.3.0/openmpi-4.1.4.1
export jasper=/home/wrf/WRF_Model/libraries/asper-1.900.1/install/
export JASPERLIB=/home/wrf/WRF_Model/libraries/jasper-1.900.1/install/lib
export JASPERINC=/home/wrf/WRF_Model/libraries/jasper-1.900.1/install/include
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export WRF_DIR=/home/wrf/WRF_Model/WRF_Model/WRF
export LD_LIBRARY_PATH="$NETCDFC/lib:$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$OPENMPIF/lib"
export LIBRARY_PATH="$NETCDFC/lib:$NETCDF/lib:$JASPERLIB:$HDF5/lib:$OPENMPI/lib:$OPENMPIF/lib:$LIBRARY_PATH"
export WRFDA=true # true|false