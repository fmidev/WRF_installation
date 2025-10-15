####################################
# Read GFS forecast and save to SQLite #
####################################

# Parse command line arguments - expecting forecast date in format yyyymmddHH
args = commandArgs(trailingOnly=TRUE)
if (length(args) != 1 || nchar(args[1]) != 10){
  stop("Usage: Rscript read_forecast_gfs.R <yyyymmddHH>\n  Example: Rscript read_forecast_gfs.R 2024010100")
}
datetime = args[1]

# Load required libraries for forecast processing and GRIB handling
library(harp)

# Function to inspect GRIB file contents and verify variables
inspect_grib <- function(file_path) {
  tryCatch({
    if (!file.exists(file_path)) {
      cat("File does not exist:", file_path, "\n")
      return(FALSE)
    }
    
    # For GRIB files, we can use system commands to inspect
    cat("GRIB file found, checking contents...\n")
    system(paste("grib_ls", file_path, "| head -20"), ignore.stdout = FALSE)
    return(TRUE)
  }, error = function(e) {
    cat("Error inspecting GRIB file:", e$message, "\n")
    cat("Note: Make sure grib_ls is available or install eccodes tools\n")
    return(FALSE)
  })
}

# Set up paths and configuration for forecast processing
station_list <- read.csv("/wrf/WRF_Model/Verification/Data/Static/stationlist_KYR.csv")
file_path <- "/wrf/WRF_Model/Verification/Data/Forecast" 
template <- "{fcst_model}_{YYYY}{MM}{DD}{HH}"
sql_folder <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
fcst_model <- "gfs"
forecast_file <- paste0(file_path, "/", fcst_model, "_", datetime)

# Define GFS variable names and their mapping
# These should match the variables extracted in the verification.sh script
gfs_vars <- c("t2m", "ws10m", "q2m", "psfc", "topo", "pcp")

cat("Processing GFS forecast for date:", datetime, "\n")
cat("Using model:", fcst_model, "\n")

# Check if forecast file exists
if (!file.exists(forecast_file)) {
  cat("ERROR: Forecast file not found:", forecast_file, "\n")
  cat("Files in directory", file_path, ":\n")
  print(list.files(file_path, pattern = fcst_model))
  stop(paste0("Forecast file not found: ", forecast_file))
}

# Inspect GRIB file to verify variables
cat("Forecast file found! Inspecting contents...\n")
inspect_grib(forecast_file)

# Process and write forecast data
cat("Reading forecast data and writing to SQLite...\n")
tryCatch({
  read_forecast(
    dttm = datetime,
    fcst_model = fcst_model,
    parameter = gfs_vars,
    file_format = "grib",
    file_format_opts = grib_opts(
      param_find = list(
        "q2m" = "2sh",
      )
    ),
    lead_time = seq(0, as.numeric(Sys.getenv("LEADTIME")), 1),
    transformation = "interpolate",
    transformation_opts = interpolate_opts(
      stations = station_list,
      method = "bilinear",
      clim_param = "topo"
    ),
    file_path = file_path,
    file_template = template,
    output_file_opts = sqlite_opts(
      path = sql_folder,
      template = "fctable_det",
      index_cols = c("fcst_dttm", "lead_time", "SID"),
      remove_model_elev = TRUE
    ),
    return_data = FALSE
  )
  
  cat("Forecast data successfully written to SQLite\n")
}, error = function(e) {
  cat("Error processing forecast:", e$message, "\n")
   
  # Additional debugging information
  cat("Detailed error diagnostics:\n")
  cat("- File path:", file_path, "\n")
  cat("- File template:", template, "\n")
  cat("- Variables requested:", paste(gfs_vars, collapse=", "), "\n")
}) 
 
cat("GFS forecast processing completed\n")