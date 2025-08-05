# WRF Installation Guide

This guide explains how to install and set up the WRF weather model and its tools. It provides complete instructions for running the model automatically for operational forecasting.

## System Requirements

Before starting, please check:

   - CPU: WRF can run on one core but works best with multiple cores
   - Disk space:
     - 100GB for geographical data
     - 100-200GB for model files (depends on your domain size)
     - For testing: 300GB is sufficient
     - For operational use: at least 1TB is recommended

For complete WRF documentation, visit the [WRF User's Guide](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/index.html)

## Automated Installation

Follow these steps for easy installation:

1. **Install Git**:
   ```bash
   sudo dnf install git
   ```

2. **Get the Code**:
   ```bash
   git clone https://github.com/fmidev/WRF_installation.git
   cd WRF_installation
   ```

3. **Run the Installation**:
   ```bash
   chmod +x installation.sh
   ./installation.sh
   ```

4. **What the Script Does**:
   - Installs all required dependencies
   - Downloads and builds necessary libraries
   - Compiles WRF, WPS, WRFDA, and UPP
   - Sets up environment variables
   - Creates directory structure for operational use
   - Sets up cronjobs for automated runs
   - Downloads geographical data and CRTM coefficients
   - Copies configuration and run scripts

## Domain Setup Guide

You can easily create WRF domains using [WRF Domain Wizard](https://wrfdomainwizard.net/):

1. Click "New" in the sidebar and draw your main domain on the map. This will be your outer domain with the base resolution (default 12 km).
2. Click "Add Nest" to add an inner domain and adjust it on the map.
3. Set the inner domain resolution using "Parent_grid_ratio" - the default is 3, which means 4 km resolution if your outer domain is 12 km.
4. Click "Save" to download the domain settings (namelist.wps) for your WRF setup.

## Operational Workflow

### Environment Setup

The `env.sh` script in the `WRF_Model/scripts` directory contains all necessary settings for WRF:

1. **Main Settings**:
   - **Library Paths**: NetCDF, HDF5, OpenMPI and other libraries
   - **Program Locations**: WRF, WPS and WRFDA directories
   - **Run Settings**: Forecast length, time between runs, etc.
   - **Folders**: Data, observations, and results directories

2. **Workflow Controls**:
   The script has simple on/off switches to control which components run:
   ```bash
   export RUN_CHECK_BOUNDARY_FILES=true  # Check if boundary files exist
   export RUN_GET_OBS=true               # Download observations
   export RUN_WPS=true                   # Run preprocessing
   export RUN_WRF=true                   # Run WRF model
   export WRFDA=false                    # Use data assimilation
   export RUN_UPP=false                  # Run post-processor
   export RUN_VERIFICATION=false         # Run verification tools
   ```

3. **Using the Script**:
   The scripts use this automatically, but you can also test/use it directly:
   ```
   source WRF_Model/scripts/env.sh
   ```

### Boundary Data
WRF needs boundary data in GRIB format. Use the `Download_GFS/get_gfs.sh` script to download GFS data. The `Download_GFS/gfs.cnf` file sets the area, resolution, and forecast hours. Make sure the data goes to the correct folder (default: `/home/{user}/WRF_Model/GFS`). The script always downloads the newest data.

```
./get_gfs.sh
```

### Preprocessing
Before running WPS (WRF Preprocessing System), you need to download geographical data (if installing manually). This data includes terrain height, land use types, and soil information:

```
# Download full dataset (~100GB)
wget -P /path/to/WPS_GEOG/ https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz 
# Or download smaller high-resolution data (~30GB)
wget -P /path/to/WPS_GEOG/ https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz 
# Extract the files
cd /path/to/WPS_GEOG/
tar -zxvf geog_complete.tar.gz --strip-components=1
tar -zxvf geog_high_res_mandatory.tar.gz --strip-components=1
```

Next, set up your domain in `WRF_Model/scripts/Run_WPS.sh` and `WRF_Model/scripts/Run_WRF.sh`:

1. **Domain Settings**: Copy settings from your WRF Domain Wizard file (namelist.wps):
   - Center point location (`ref_lat`, `ref_lon`)
   - Grid size (`e_we`, `e_sn`)
   - Grid spacing (`dx`, `dy`)
   - Nesting ratios (`parent_grid_ratio`)
   - Map type (`map_proj`)

2. **File Locations**: Check all folder paths (these should be correct if you used automated installation):
   - WPS program location
   - Geographical data location
   - Input/output folders

3. **CPU Usage**: Set the number of CPUs based on your computer:
   ```
   mpirun -np 24 ./geogrid.exe  # Uses 24 CPU cores
   ```

Test your WPS setup:
```
# Format: ./Run_WPS.sh <year> <month> <day> <hour> <forecast_hours> <output_folder>
# Example: 48-hour forecast starting September 10, 2024, 01:00 UTC
./Run_WPS.sh 2024 09 10 01 48 /home/username/WRF_Model/out/
```

If successful, this creates the input files needed for WRF.

### Observations (Optional for Data Assimilation)
For data assimilation, you need observation data. The system uses NCEP's real-time database.

1. **Data Types**: The `get_obs.sh` script downloads satellite data and global observations from [NCEP](https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/).

2. **Limitations**: 
   - NCEP only keeps 2-3 days of recent data
   - Local data, radar data, and custom observations need special formatting (not included)

3. **Getting Data**: Run the script with date and time:
   ```
   # Format: ./get_obs.sh <year> <month> <day> <hour>
   # Example: Get data for September 10, 2024, 01:00 UTC
   ./get_obs.sh 2024 09 10 01
   ```

4. **Result**: The script organizes files for WRFDA to use.

### Running the Model
The `Run_WRF.sh` script manages the WRF model run, including optional data assimilation.

1. **Setup**: Before running, check these settings:
   - **Model Options**: Make sure physics options, time steps, and domain settings match your needs. See the [WRF User's Guide](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/namelist_variables.html) for all options.
   
   - **Folder Paths**: Check all paths (should be correct if using automated installation):
     - WRF program location
     - Input/output folders
     - Working folders
   
   - **CPU Count**: Set the number of processors for best performance
   
   - **Data Assimilation**: Check these settings if using WRFDA

2. **Running the Model**:
   ```
   # Format: ./Run_WRF.sh <year> <month> <day> <hour> <forecast_hours> <output_folder>
   # Example: 48-hour forecast starting September 10, 2024, 01:00 UTC
   ./Run_WRF.sh 2024 09 10 01 48 /home/username/WRF_Model/out/
   ```

3. **Using Data Assimilation**:
   - Set `WRFDA=true` in your `env.sh` file
   - Make sure CRTM files are available for satellite data
   - Provide proper background error statistics

### Post-processing
UPP (Unified Post Processor) converts WRF output (NetCDF) to GRIB format. The `installation` file shows how to compile UPP. The `setup_upp` file explains how to set up UPP (not needed with automated installation). The `Run_scripts/execute_upp.sh` script converts NetCDF to GRIB automatically.

### Verification
Instructions for using HARP verification with WRF will be added in the future.

### Cleaning and Automation
The `clean_wrf` script removes old GFS, WRF, and UPP files. You can set this up to run automatically once a day.

For fully automated operation, use the `control_run_WRF.sh` script to run all steps. It's best to test each part separately first. Run it with:
```
./control_run_WRF.sh <analysis_hour>
```

