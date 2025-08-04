#################################################
## Convert observation CSV files to SQLite format
#################################################

args = commandArgs(trailingOnly=TRUE)
if (length(args) != 1){
  stop("Give current date as input argument in yyyymmddHH format, E.g. Rscript R_OBS_csv_sqlite.R 2023103100")
}

current_date = args[1]

# Validate the current date format
if (nchar(current_date) != 10){
  stop("Current date should be in yyyymmddHH format, E.g. 2023103100")
}

library(harpIO)  # Use harpIO instead of just harp
library(dplyr)
library(lubridate)
library(tibble)

# Set paths
cat("Starting observation conversion for date:", current_date, "\n")
obs_path <- "/wrf/WRF_Model/Verification/Data/Obs"
sqlite_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

# Construct observation filename based on the current_date
obs_file <- file.path(obs_path, paste0("local_obs", current_date, "00_verif.csv"))

# Check if the file exists
if (!file.exists(obs_file)) {
  stop("Observation file not found: ", obs_file)
}

# Read the observation file
cat("Reading observation file:", obs_file, "\n")
obs_data <- tryCatch({
  read.csv(obs_file, stringsAsFactors = FALSE, sep="\t")
}, error = function(e) {
  stop("ERROR reading file: ", e$message)
})

# Check if data was loaded successfully
if (is.null(obs_data) || nrow(obs_data) == 0) {
  stop("No data found in the observation file")
}

# Convert the valid_dttm to POSIXct if it's a character
if (is.character(obs_data$valid_dttm)) {
  obs_data$valid_dttm <- as.POSIXct(obs_data$valid_dttm, format="%Y-%m-%d %H:%M:%S", tz="UTC")
}

cat("Found", nrow(obs_data), "total observation records in file\n")

# Define a custom reader function similar to the example
read_csv_obs <- function(file_name, dttm, parameter = NULL, ...) {
  
  # read the csv data
  obs_data <- read.csv(file_name, stringsAsFactors = FALSE, sep="\t")
  
  # Convert the valid_dttm to POSIXct if it's a character
  if (is.character(obs_data$valid_dttm)) {
    obs_data$valid_dttm <- as.POSIXct(obs_data$valid_dttm, format="%Y-%m-%d %H:%M:%S", tz="UTC")
  }
  
  # Make sure we have all required columns and convert to numeric as needed
  obs_data <- obs_data %>%
    select(valid_dttm, SID, lat, lon, elev, T2m, Wdir, WS, Pressure) %>%
    mutate(
      T2m = as.numeric(T2m),
      WS = as.numeric(WS),
      Wdir = as.numeric(Wdir),
      Pressure = as.numeric(Pressure)
    ) %>%
    filter(!is.na(valid_dttm), !is.na(SID))  # Filter out any rows with missing key values
  
  # Define parameter units
  obs_units <- tibble::tribble(
    ~parameter, ~accum_hours, ~units,
    "T2m"      , 0, "K",
    "WS"       , 0, "m/s",
    "Wdir"     , 0, "degrees",
    "Pressure" , 0, "hPa"
  )
  
  # Return the data as a named list
  list(synop = obs_data, synop_params = obs_units)
}

# Instead of using register_format_fn which isn't available, we'll use a different approach
# using RSQLite directly to create the SQLite database

# Check if RSQLite is installed, install if not
if (!requireNamespace("RSQLite", quietly = TRUE)) {
  cat("Installing RSQLite package...\n")
  install.packages("RSQLite")
}
library(RSQLite)

# Extract year and month from the current date to create monthly file
date_parts <- substring(current_date, 1, 8)  # Get YYYYMMDD part
year_month <- substring(date_parts, 1, 6)    # Get YYYYMM part

# Create a filename using the year and month
sqlite_filename <- paste0("obstable_monthly_", year_month, ".sqlite")
sqlite_file <- file.path(sqlite_dir, sqlite_filename)

cat("Using monthly SQLite database:", sqlite_file, "\n")

tryCatch({
  # Create SQLite connection
  con <- dbConnect(SQLite(), sqlite_file)
  
  # Check if the table exists in the database
  table_exists <- dbExistsTable(con, "observations")
  
  if (table_exists) {
    cat("Existing observations table found. Checking for duplicates...\n")
    
    # Get existing records to check for duplicates
    # We'll use a query to identify unique combinations of valid_dttm and SID
    existing_keys <- dbGetQuery(con, "SELECT valid_dttm, SID FROM observations")
    
    # Convert timestamps to ensure consistent format for comparison
    if (is.character(existing_keys$valid_dttm)) {
      existing_keys$valid_dttm <- as.POSIXct(existing_keys$valid_dttm, format="%Y-%m-%d %H:%M:%S", tz="UTC")
    }
    
    # Create a unique key for each record by combining timestamp and station ID
    existing_keys$unique_key <- paste(existing_keys$valid_dttm, existing_keys$SID)
    obs_data$unique_key <- paste(obs_data$valid_dttm, obs_data$SID)
    
    # Filter out records that already exist
    new_records <- obs_data[!(obs_data$unique_key %in% existing_keys$unique_key),]
    
    cat("Found", nrow(new_records), "new records out of", nrow(obs_data), "total records\n")
    
    if (nrow(new_records) > 0) {
      # Remove the temporary key column before writing
      new_records$unique_key <- NULL
      
      # Append new records to the existing table
      dbWriteTable(con, "observations", new_records, append = TRUE)
      cat("Added new observation records to the database\n")
    } else {
      cat("No new records to add\n")
    }
    
    # Clean up the temporary column from the original data frame too
    obs_data$unique_key <- NULL
    
  } else {
    # Table doesn't exist, create it with all records
    cat("Creating new observations table\n")
    dbWriteTable(con, "observations", obs_data, overwrite = TRUE)
    
    # Add indexes for faster queries
    dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_valid_dttm ON observations (valid_dttm)")
    dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_SID ON observations (SID)")
    cat("Created new SQLite database with", nrow(obs_data), "records\n")
  }
  
  # Close the connection
  dbDisconnect(con)
  
  cat("Monthly observation data successfully processed in SQLite database:", sqlite_file, "\n")
}, error = function(e) {
  cat("ERROR with SQLite operations:", e$message, "\n")
})

cat("Observation processing completed\n")