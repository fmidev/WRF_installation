# WRF_installation 
This repository provides documentation on how to compile and install the WRF model and the necessary tools for it. It also outlines the workflow and explains how to set it up so that the model runs are automated and can be used operationally.

## Downloading of libraries and compiling of source code
The text file `installation` provides a step-by-step guide on how to install and compile all the needed libraries. Similar instructions are also provided for the WRF source code and its pre/post-processing tools. Following these instructions will ensure that all the necessary binaries for running the WRF model are installed correctly. When running the WRF model or its tools, it is necessary to define some environment variables. By running `source wrf_env.sh` before executing the model, the correct variables and paths are ensured to be in place. Note that in paths, `user` has to be replaced with the correct username.

## Domain maker

## Work flow

### Boundaries
Scripts for copying GFS data
### Preprosessing
Scripts how to use WPS
### The model
Scripts for running the model, possibly DA as well 
### Postprocessing
ARWpost for visualizations, UPP for NETCDF to grib conversion, Data to smarmet scripts
### Cleaning and automization
Scripts for cleaning and automization (cronjobs...)

