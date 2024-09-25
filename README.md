# WRF_installation 
This repository provides documentation on how to compile and install the WRF model and the necessary tools for it. It also outlines the workflow and explains how to set it up so that the model runs are automated and can be used operationally.

## Downloading of libraries and compiling of source code
The text file `installation` provides a step-by-step guide on how to install and compile all the needed libraries. Similar instructions are also provided for the WRF source code and its pre/post-processing tools. Following these instructions will ensure that all the necessary binaries for running the WRF model are installed correctly. When running the WRF model or its tools, it is necessary to define some environment variables. By running `source wrf_env.sh` before executing the model, the correct variables and paths are ensured to be in place. Note that in paths, `user` has to be replaced with the correct username.

## Domain maker
Desired domains can be easily drawn with [WRF Domain Wizard](https://wrfdomainwizard.net/)
## Work flow

### Boundaries
Scripts for copying GFS data
### Preprosessing
Scripts how to use WPS
### The model
Scripts for running the model, possibly DA as well 
### Postprocessing
Unified Post Processor (UPP) can be used to convert WRF NetCDF output to Grib. Instructions how to compile UPP can be found from the `installation`. The text file `setup_upp` describes how to setup UPP as a WRF postprosessing tool and with `execute_upp` the UPP can be easily used to automated NETCDF -> GRIB conversion.      
### Cleaning and automization
`clean_wrf` script cleans GFS boundary files, WRF and UPP output files.

