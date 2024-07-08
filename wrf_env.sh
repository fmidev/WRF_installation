#!/bin/bash
export PATH="$HOME/.local/bin:$HOME/bin:/home/user/libs/openmpi-4.1.6/install_dir/bin:/home/user/libs/netcdf-c-4.9.2/install_dir/bin:$PATH"
export WRF_EM_CORE=1
export NETCDF=/home/user/libs/netcdf-c-4.9.2/install_dir
export NETCDF4=1
export HDF5=/home/user/libs/hdf5-1.14.3/install_dir
export jasper=/home/user/libs/jasper-1.900.1/install_dir
export JASPERLIB=/home/user/libs/jasper-1.900.1/install_dir/lib
export JASPERINC=/home/user/libs/jasper-1.900.1/install_dir/include
export WRF_DA_CORE=0
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export WRF_DIR=/home/user/WRF
export LD_LIBRARY_PATH="/home/user/libs/netcdf-c-4.9.2/install_dir/lib:$JASPERLIB:$HDF5/lib"

