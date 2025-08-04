####################################
# Read_forecast and save to SQLite #
####################################

args = commandArgs(trailingOnly=TRUE)
if (length(args) != 1){
  stop("Give forecast date/time as input argument in yyyymmddHH format, E.g. Rscript read_forecast_wrf_d02.R 2024010100")
}

datetime = args[1] 
if (nchar(datetime) != 10){
  stop("Give forecast date/time as input argument in yyyymmddHH format, E.g. Rscript read_forecast_wrf_d02.R 2024010100")
}

# Load required libraries
library(harp)
library(ncdf4)

# Function to inspect NetCDF file contents - simplified version
inspect_netcdf <- function(file_path) {
  tryCatch({
    if (!file.exists(file_path)) {
      cat("File does not exist:", file_path, "\n")
      return(FALSE)
    }
    
    # Try to open the file and inspect variables
    nc <- nc_open(file_path)
    cat("NetCDF file variables:", paste(names(nc$var), collapse=", "), "\n")
    nc_close(nc)
    return(TRUE)
  }, error = function(e) {
    cat("Error inspecting NetCDF file:", e$message, "\n")
    return(FALSE)
  })
}

# Load station list
station_list <- read.csv("/wrf/WRF_Model/Verification/Data/Static/stationlist_KYR.csv")
file_path <- "/wrf/WRF_Model/Verification/Data/Forecast" 
template <- "{fcst_model}_{YYYY}{MM}{DD}{HH}"
sql_folder <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"

cat("Processing forecast for date:", datetime, "\n")
cat("Using model: wrf_d02\n")

# Check if forecast file exists
forecast_file <- paste0(file_path, "/wrf_d02_", datetime)
if (!file.exists(forecast_file)) {
  stop(paste0("Forecast file not found: ", forecast_file))
}

# Quick check of NetCDF variables
inspect_netcdf(forecast_file)

# Process and write forecast data using direct variable names
tryCatch({
  cat("Reading forecast with direct variable mapping...\n")
  read_forecast(
    dttm           = datetime,
    fcst_model     = "wrf_d02",
    parameter      = c("T2", "U10", "V10", "RAINC", "RAINNC", "PSFC", "Q2"),
    file_format    = "netcdf",
    file_format_opts = netcdf_opts(
      "wrf",
      param_find = list(
        "T2" = "T2",
        "U10" = "U10", 
        "V10" = "V10",
        "RAINC" = "RAINC",
        "RAINNC" = "RAINNC", 
        "PSFC" = "PSFC",
        "Q2" = "Q2"
      )
    ),
    lead_time      = seq(0, 40, 1),
    transformation = "interpolate",
    transformation_opts = interpolate_opts(
      stations = station_list,
      method = "bilinear",
      clim_param = "topo"
    ),
    file_path      = file_path,
    file_template  = template,
    output_file_opts = sqlite_opts(
      path = sql_folder,
      template = "fctable_det",
      index_cols = c("fcst_dttm", "lead_time", "SID"),
      remove_model_elev = TRUE
    ),
    return_data    = FALSE
  )
  cat("Forecast data successfully written to SQLite\n")
}, error = function(e) {
  cat("Error processing forecast:", e$message, "\n")
})

cat("Forecast processing completed for wrf_d02\n")

if (!file.exists(forecast_file)) {
  cat("ERROR: Forecast file not found:", forecast_file, "\n")
  # Look for files in the directory
  cat("Files in directory", file_path, ":\n")
  dir_files <- list.files(file_path, pattern = "wrf_d02_")
  print(dir_files)
  stop(paste0("Forecast file not found: ", forecast_file))
}

cat("Forecast file found!\n")
# Inspect the NetCDF file content before passing to read_forecast
inspect_netcdf(forecast_file)

# List available parameter mappings from harp
cat("Available parameter mappings in harp for WRF:\n")
tryCatch({
  wrf_params <- get_param_defs("wrf")
  print(names(wrf_params))
}, error = function(e) {
  cat("Error getting WRF parameter definitions:", e$message, "\n")
})

# Get netcdf options to check if "wrf" format is supported
cat("NetCDF options for WRF:\n")
tryCatch({
  wrf_opts <- netcdf_opts("wrf")
  print(wrf_opts)
}, error = function(e) {
  cat("Error getting WRF NetCDF options:", e$message, "\n")
})

cat("Attempting to read forecast with parameters: T2m, WS10m, Pcp, PSFC, Q2\n")
cat("Using file path:", file_path, "\n")
cat("Using file template:", template, "\n")

# Create a custom parameter mapping for WRF
cat("Setting up custom parameter mapping for WRF...\n")
tryCatch({
  # Create parameter mapping based on actual variables in the file
  wrf_params <- list(
    "T2m" = "T2",      # Map T2m to T2
    "WS10m" = c("U10", "V10"), # Wind speed requires both components
    "Pcp" = c("RAINC", "RAINNC"), # Total precipitation is sum of these
    "Pressure" = "PSFC",   # Surface pressure
    "Q2m" = "Q2"       # Specific humidity
  )
  
  # Register the parameter mapping with harp
  cat("Custom parameter mapping created\n")
}, error = function(e) {
  cat("Error creating parameter mapping:", e$message, "\n")
})

cat("Attempting to read forecast with direct variable names matching the NetCDF file\n")

# Try to read the forecast with more detailed error handling
tryCatch({
  # Use exact variable names from the NetCDF file
  wrf_point <- read_forecast(
    dttm           = datetime,
    fcst_model     = "wrf_d02",
    parameter      = c("T2", "U10", "V10", "RAINC", "RAINNC", "PSFC", "Q2"), # Use exact variable names
    file_format    = "netcdf",
    file_format_opts = netcdf_opts(
      "wrf",
      param_find = list(
        "T2" = "T2",
        "U10" = "U10", 
        "V10" = "V10",
        "RAINC" = "RAINC",
        "RAINNC" = "RAINNC", 
        "PSFC" = "PSFC",
        "Q2" = "Q2"
      )
    ),
    lead_time      = seq(0, 40, 1),
    transformation = "interpolate",
    transformation_opts = interpolate_opts(
      stations = station_list,
      method = "bilinear",
      clim_param = "topo" #parameter for topography 
    ),
    file_path      = file_path,
    file_template  = template,
    output_file_opts = sqlite_opts(
      path = sql_folder,
      template = "fctable_det",
      index_cols = c("fcst_dttm", "lead_time", "SID"),
      remove_model_elev = TRUE
    ),
    return_data    = TRUE # Temporarily set to TRUE for debugging
  )
  
  # Check if any data was returned
  if (!is.null(wrf_point) && length(wrf_point) > 0) {
    cat("Successfully read forecast data!\n")
    if (is.data.frame(wrf_point)) {
      cat("Data dimensions:", nrow(wrf_point), "rows x", ncol(wrf_point), "columns\n")
    } else {
      cat("Data returned but not as a data frame. Structure:", str(wrf_point), "\n")
    }
    
    # Write to SQLite with return_data = FALSE
    cat("Writing data to SQLite...\n")
    read_forecast(
      dttm           = datetime,
      fcst_model     = "wrf_d02",
      parameter      = c("T2", "U10", "V10", "RAINC", "RAINNC", "PSFC", "Q2"),
      file_format    = "netcdf",
      file_format_opts = netcdf_opts(
        "wrf",
        param_find = list(
          "T2" = "T2",
          "U10" = "U10", 
          "V10" = "V10",
          "RAINC" = "RAINC",
          "RAINNC" = "RAINNC", 
          "PSFC" = "PSFC",
          "Q2" = "Q2"
        )
      ),
      lead_time      = seq(0, 40, 1),
      transformation = "interpolate",
      transformation_opts = interpolate_opts(
        stations = station_list,
        method = "bilinear",
        clim_param = "topo"
      ),
      file_path      = file_path,
      file_template  = template,
      output_file_opts = sqlite_opts(
        path = sql_folder,
        template = "fctable_det",
        index_cols = c("fcst_dttm", "lead_time", "SID"),
        remove_model_elev = TRUE
      ),
      return_data    = FALSE
    )
    cat("Data successfully written to SQLite\n")
  } else {
    cat("Warning: No data was returned from read_forecast\n")
    
    # Alternative approach: Try a direct ncdf4 reading approach
    cat("Trying direct ncdf4 approach to inspect lead times...\n")
    tryCatch({
      nc <- nc_open(forecast_file)
      time_var <- ncvar_get(nc, "Times")
      cat("Time variable shape:", dim(time_var), "\n")
      cat("First few time values:\n")
      if (is.array(time_var) && length(dim(time_var)) > 1) {
        # Handle character array
        times <- apply(time_var, 1, function(x) paste(x, collapse=""))
        print(head(times))
      } else {
        print(head(time_var))
      }
      nc_close(nc)
      
      # Try with just a subset of lead times
      cat("Trying with a subset of lead times (0-10)...\n")
      wrf_point_subset <- read_forecast(
        dttm           = datetime,
        fcst_model     = "wrf_d02",
        parameter      = c("T2"),
        file_format    = "netcdf",
        file_format_opts = netcdf_opts("wrf"),
        lead_time      = seq(0, 10, 1),
        transformation = "interpolate",
        transformation_opts = interpolate_opts(
          stations = station_list,
          method = "bilinear",
          clim_param = "topo"
        ),
        file_path      = file_path,
        file_template  = template,
        return_data    = TRUE
      )
      cat("Subset lead time approach result:", !is.null(wrf_point_subset) && length(wrf_point_subset) > 0, "\n")
    }, error = function(e) {
      cat("Direct ncdf4 approach failed:", e$message, "\n")
    })
  }
}, error = function(e) {
  cat("Error in read_forecast:", e$message, "\n")
  
  # Try a completely different approach - read without transformation
  cat("Trying to read without transformation...\n")
  tryCatch({
    raw_data <- read_forecast(
      dttm           = datetime,
      fcst_model     = "wrf_d02",
      parameter      = "T2",
      file_format    = "netcdf",
      file_format_opts = netcdf_opts("wrf"),
      lead_time      = seq(0, 40, 1),
      file_path      = file_path,
      file_template  = template,
      return_data    = TRUE
    )
    cat("Raw data read successful. Now attempting transformation separately.\n")
  }, error = function(e2) {
    cat("Reading without transformation also failed:", e2$message, "\n")
  })
})

cat("Forecast processing completed for wrf_d02\n")

