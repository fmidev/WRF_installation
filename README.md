# WRF Installation Guide

This repository provides a complete automated workflow for installing, configuring, and running the WRF (Weather Research and Forecasting) model for operational forecasting. The setup includes data assimilation, post-processing, verification, and a pre-operational testing environment.

## What It Does

- **Installation**: One script installs everything: WRF, WPS, WRFDA, UPP, and all dependencies
- **Operational Workflow**: Ready-made scripts for model runs with GFS boundary data
- **Data Assimilation**: WRFDA with support for satellite and conventional observations
- **Testing Environment**: Parallel WRF_test setup for pre-operational testing
- **Verification Tools**: Harp-based verification with harpVis visualizations
- **Visualization**: Interactive Shiny app for exploring WRF NetCDF output with animated maps and time series
- **Post-Processing**: UPP for NetCDF to GRIB conversion
- **Local Observations**: Template for pre-processing country-specific observation data

## System Requirements

Before starting, please check:

- **CPU**: WRF can run on one core but works best with multiple cores
- **Disk Space**:
  - 100 GB for geographical data
  - 100-200 GB for model files (varies with domain size)
  - 300 GB minimum for testing
  - 1 TB+ recommended for operational use
- **OS**: Linux (Installation is only tested on RHEL/Rocky Linux)

For detailed WRF documentation, see the [WRF User's Guide](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/index.html)

## Quick Start

### Installation

The installation script handles everything automatically:

```bash
# Install git if needed
sudo dnf install git

# Clone the repository
git clone https://github.com/fmidev/WRF_installation.git
cd WRF_installation

# Run the installer
chmod +x installation.sh
./installation.sh
```

The script will:
- Install system dependencies (compilers, libraries)
- Build all required libraries (NetCDF, HDF5, OpenMPI, etc.)
- Compile WRF, WPS, WRFDA, and UPP
- Set up directory structure for production and testing
- Download geographical data and CRTM coefficients
- Configure cron jobs for daily runs
- Install R packages and verification tools (if GitHub token provided)
- Set up the harpVis Shiny server (if GitHub token provided)

The installation takes a few hours, so grab a coffee and let it run.

## Setting Up Your Domain

Use the [WRF Domain Wizard](https://wrfdomainwizard.net/) to design your model area:

1. Click "New" and draw your outer domain
2. Click "Add Nest" to add inner domains with higher resolution
3. Set the resolution ratio with "Parent_grid_ratio" (3 = 3× finer resolution)
4. Click "Save" to download the `namelist.wps` file

### Automated Domain Configuration

Just save your downloaded `namelist.wps` file as `domain.txt` in the scripts directory (`$BASE/scripts/`). The scripts automatically read:

- Grid dimensions (`e_we`, `e_sn`)
- Nesting parameters (`parent_grid_ratio`, `i_parent_start`, `j_parent_start`)
- Grid spacing (`dx`, `dy`)
- Map projection settings (`map_proj`, `ref_lat`, `ref_lon`, etc.)

Some settings like `max_dom` (number of domains) and `interval_seconds` (boundary update frequency) are hardcoded in the scripts and can be edited if needed.

**Note for Mercator Projection Users**: If you're using Mercator projection (`map_proj = 'mercator'`) with data assimilation and local observations, set `TRUELAT1 = 0` in both your domain settings and `namelist.obsproc`. Other values will cause errors in obsproc.

## Operational Workflow

### Configuring Your Workflow

The `env.sh` script (`$BASE/scripts/env.sh`) is your central configuration file where `$BASE` is `/home/{user}/WRF_Model` as default. It contains:

**Paths and Libraries**
- Library locations (NetCDF, HDF5, OpenMPI)
- WRF, WPS, WRFDA, and UPP directories
- Data directories for input/output

**Run Configuration**
- `LEADTIME`: Forecast length in hours (default: 72)
- `INTERVAL`: Time between cycles in hours (default: 6)
- `MAX_CPU`: Number of CPU cores to use (default: Defined based on the system)
- `GRIBNUM`: Number of 3-hourly GFS files required (default: 25 (for WRF runs up to 75 hours))

**Workflow Switches** - Turn components on/off:
```bash
export RUN_CHECK_BOUNDARY_FILES=true  # Wait for boundary files
export RUN_GET_OBS=true               # Download observations
export RUN_WPS=true                   # Run preprocessing
export RUN_WRF=true                   # Run WRF model
export RUN_WRFDA=true                 # Use data assimilation
export RUN_UPP=true                   # Convert to GRIB
export RUN_VERIFICATION=true          # Run verification
export RUN_COPY_GRIB=true            # Copy to SmartMet server
```

These switches let you customize what runs in each cycle. Just set anything to `false` to skip it.

### Downloading Boundary Data

WRF needs boundary conditions from a global model. We use GFS data in GRIB format:

```bash
Download_GFS/get_gfs.sh
```

Configure the download in `gfs.cnf`:
- Geographic area to download
- Horizontal resolution
- Forecast hours needed

The script downloads the latest available GFS run and saves it to `$BASE/GFS/`. The operational workflow is not downloading GFS boundaries as default. This is because the system is designed to work with SmartMet which already does the downloading. The user have to setup `get_gfs.sh` by themselves.

### Running WPS (Preprocessing)

WPS prepares the geographical data and boundary conditions for WRF. The installation script automatically downloads the geographical data (terrain, land use, soil types).

If you need to download it manually:
```bash
cd $BASE/WPS_GEOG/
wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz
wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz

# Extract
tar -zxvf geog_complete.tar.gz --strip-components=1
tar -zxvf geog_high_res_mandatory.tar.gz --strip-components=1
```

**Testing WPS Manually**

Make sure your `domain.txt` file and GFS boundaries are in place, then for example run:

```bash
cd /home/wrf/WRF_Model/scripts
./run_WPS.sh 2024 09 10 00 48
```

This processes a 48-hour forecast starting September 10, 2024 at 00 UTC. The script automatically reads your domain configuration from `domain.txt` and creates the `met_em.*` files needed by WRF.

### Data Assimilation with WRFDA

WRFDA improves forecasts by incorporating observations into the initial conditions.

**Downloading Observations**

The `get_obs.sh` script downloads global observations and satellite data from [NCEP](https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/):

```bash
./get_obs.sh 2024 09 10 00
```

**Note**: NCEP only keeps the last 2-3 days of data online. For older dates, you'll need alternative sources.

**Local Observations**

To use local observations (weather stations, etc.), you need to convert them to Little-R format. The repository provides:

- `convert_to_little_r.py`: Python script to convert CSV observations to Little-R format
- Example country-specific processing scripts in `Run_scripts/process_local_obs/`

Your CSV should include columns like:
- `station_id`, `latitude`, `longitude`, `date`
- `temperature`, `pressure`, `wind_speed`, `wind_direction`, `relative_humidity`

See the script header for detailed format requirements.


### Running WRF

The `run_WRF.sh` script handles the model execution, including optional data assimilation.

**Manual Test Run**

```bash
cd /home/wrf/WRF_Model/scripts
./run_WRF.sh 2024 09 10 00 48
```

This runs a 48-hour forecast starting September 10, 2024 at 00 UTC.

**Using Data Assimilation**

To enable WRFDA, make sure you have:
- CRTM coefficients (downloaded during installation)
- Background error statistics (`be.dat` file)
- Observation data (from `get_obs.sh`)

The installation sets up generic `be.dat` file. For more fine-tuned assimiliation process, domain specific background error statistics must be created. Instruction for that is provided later. The `run_WRFDA.sh` script automatically runs WRFDA before WRF if enabled, creating improved initial conditions.

**Customizing Physics**

Edit `run_WRF.sh` to change physics parameterizations (microphysics, radiation, PBL schemes, etc.) if needed. See the [WRF User's Guide](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/namelist_variables.html) for all options.

### Post-Processing with UPP

UPP (Unified Post Processor) converts WRF's NetCDF output to GRIB2 format, which is needed format for SmartMet system.

```bash
./execute_upp.sh 2024 09 10 00
```

The script processes all forecast hours and outputs GRIB2 files to `$BASE/UPP_out/`.

**SmartMet Integration**

If you have a SmartMet server, set `RUN_COPY_GRIB=true` in `env.sh` and configure the server details in `control_run_WRF.sh`. The system will automatically rsync GRIB files and trigger ingestion.

### Forecast Verification

The verification system uses R and the harp package to compare forecasts against observations.

**How It Works**

The `verification.sh` script:
1. Extracts variables from WRF and GFS output files
2. Converts observations from CSV to SQLite format (`read_obs.R`)
3. Interpolates forecasts to station locations (`read_forecast_wrf.R` and `read_forecast_gfs.R`)
4. Computes verification statistics (`verify_parameters.R`)


**Running Verification**

```bash
./verification.sh 2024 09 10 00
```

The system automatically runs weekly and monthly verification on Wednesday at 12 UTC.

**Viewing Results - Shiny Server Web Applications**

The installation sets up a Shiny server with two interactive web applications for visualization and analysis.

**Accessing the Applications**

**Local Access** (if you have a desktop on the WRF server):
- harpVis: `http://localhost:3838/harpvis/`
- WRF Visualization: `http://localhost:3838/wrf-viz/`

**Remote Access** (SSH tunnel from your computer):
```bash
ssh -L 8080:localhost:3838 wrf@your-wrf-server-ip
```
Then open:
- harpVis: `http://localhost:8080/harpvis/`
- WRF Visualization: `http://localhost:8080/wrf-viz/`

**harpVis** - Verification analysis and statistics:
- Generate verification plots (bias, RMSE, scatter, etc.)
- Compare multiple forecasts
- Export statistics and figures

**WRF Visualization** - Interactive forecast exploration:
- Animated maps of WRF output variables (temperature, precipitation, wind, etc.)
- Point time series extraction

**Note**: The Shiny server is only installed if you provide a GitHub Personal Access Token during installation (needed for harp packages).

### WRF_test - Pre-Operational Testing

The installation creates a parallel testing environment (`/WRF_test/`) where you can safely test changes before deploying to production.

**What Makes It Different**

- **Isolated runs**: Separate output directories, logs, and working files
- **Lighter schedule**: Runs only at 00 and 12 UTC (vs. every 6 hours in production)
- **Reduced CPU**: Uses fewer cores (default: 4) to avoid interfering with production
- **Shared resources**: Uses the same executables, libraries, and GFS data as production
- **Same domain**: Automatically reads `domain.txt` from production scripts

**Testing Changes**

Test runs work just like production runs:

```bash
cd /home/wrf/WRF_test/scripts

# Full test cycle
./control_run_WRF_test.sh 00

# Or run components individually
./run_WPS_test.sh 2024 09 10 00
./run_WRF_test.sh 2024 09 10 00 48
./verification_test.sh 2024 09 10 00
```

Configure test runs in `env_test.sh` (same format as production's `env.sh`).

**Automated Testing**

Cron runs test forecasts twice daily:
```
30 0,12 * * * cd /home/wrf/WRF_test/scripts && ./control_run_WRF_test.sh ...
```

**Deploying to Production**

Once you've tested changes successfully, you can deploy them to production. The `deploy_test_to_prod.sh` script helps with this (Not working properly yet, still under development), but review changes carefully before deploying!


### Automated Operations

**Full Forecast Cycle**

The `control_run_WRF.sh` script orchestrates the entire workflow:

```bash
./control_run_WRF.sh 00
```

This runs everything:
1. Checks for boundary files
2. Downloads observations
3. Runs WPS
4. Runs WRFDA
5. Runs WRF
6. Runs UPP
7. Copies GRIB files
8. Runs verification

**Automated Scheduling**

The installation sets up cron jobs for automatic forecasting. By default, WRF runs every 6 hours:

```
00 00,06,12,18 * * * cd /home/wrf/WRF_Model/scripts && ./control_run_WRF.sh ...
```

**Cleaning Old Files**

The `clean_wrf.sh` script removes old data to save disk space:

```bash
./clean_wrf.sh
```

It cleans:
- Old GFS boundary files
- Old WRF output files
- Old UPP GRIB files
- Old log files

Set it to run daily with cron:
```
0 2 * * * /home/wrf/WRF_Model/scripts/clean_wrf.sh
```

## Advanced Features

### Generating Background Error Covariance (gen_be)

For optimal data assimilation performance, you should generate domain-specific background error statistics. The system includes tools to collect forecasts and generate a custom `be.dat` file.

**Collecting Forecasts**

The `WRF_test` system will save 12-hour and 24-hour forecasts from each run as default. You need at least one month of data.

**Generating Statistics**

After collecting enough data, run:
```bash
./setup_genbe_wrapper.sh
```

This script uses WRF's gen_be tools to compute background error statistics and creates a new `be.dat` file for your domain.


