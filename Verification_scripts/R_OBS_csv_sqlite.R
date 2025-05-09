#################################################
## Convert observation CSV files to SQLite format
#################################################

args = commandArgs(trailingOnly=TRUE)
if (length(args) != 2){
  stop("Give starttime and endtime as input arguments in yyyymmddHH format, E.g. Rscript R_OBS_csv_sqlite.R 2023100100 2023103123")
}

start_time = args[1]
end_time = args[2]

if (nchar(start_time) != 10 || nchar(end_time) != 10){
  stop("Give starttime and endtime as input arguments in yyyymmddHH format, E.g. Rscript R_OBS_csv_sqlite.R 2023100100 2023103123")
}

library(harp)
library(dplyr)
library(lubridate)

# Set paths
cat("Starting observation conversion for period:", start_time, "to", end_time, "\n")
obs_path <- "/home/mihasu/WRF_verification/"  # 
sqlite_dir <- "/home/mihasu/WRF_verification/"  # Path to save SQLite tables

# Create date sequence
start_date <- ymd_h(start_time)
end_date <- ymd_h(end_time)
date_seq <- seq(start_date, end_date, by = "hour")

cat("Processing", length(date_seq), "hours of observations\n")

# Format dates for file names
date_strings <- format(date_seq, "%Y%m%d%H")

# Read and process all observation CSV files
processed_data <- data.frame()
files_processed <- 0
files_missing <- 0

for (date_str in date_strings) {
  csv_file <- file.path(obs_path, paste0("test_obs_", date_str, ".csv"))
  
  if (file.exists(csv_file)) {
    cat("Processing", csv_file, "\n")
    files_processed <- files_processed + 1
    
    # Read CSV file
    obs_data <- tryCatch({
      read.csv(csv_file, stringsAsFactors = FALSE)
    }, error = function(e) {
      cat("ERROR reading file:", e$message, "\n")
      return(NULL)
    })
    
    # Format the data for harp
    if (!is.null(obs_data) && nrow(obs_data) > 0) {
      # Create valid_dttm column from Date column
      obs_data$valid_dttm <- as.POSIXct(strptime(obs_data$Date, "%Y%m%d%H"), tz = "UTC")
      
      # Rename columns to match harp convention
      obs_data <- obs_data %>%
        rename(
          SID = `Station.ID`,
          lat = Latitude,
          lon = Longitude,
          elev = Elevation
        )
      
      # Bind to processed data
      processed_data <- rbind(processed_data, obs_data)
      cat("Added", nrow(obs_data), "observation records\n")
    } else {
      cat("No valid data in file or error reading file\n")
    }
  } else {
    files_missing <- files_missing + 1
    if (files_missing <= 5) {  # Limit log spam for missing files
      cat("File not found:", csv_file, "\n")
    } else if (files_missing == 6) {
      cat("Additional missing files will not be logged individually\n")
    }
  }
}

cat("Processed", files_processed, "files,", files_missing, "files missing\n")

if (nrow(processed_data) > 0) {
  cat("Total of", nrow(processed_data), "observation records collected\n")
  
  # Convert data to harp observation object
  cat("Converting to harp observation format\n")
  
  obs_harp <- tryCatch({
    processed_data %>%
      select(valid_dttm, SID, lat, lon, elev, T2m, WS, pcp, Pressure, Q2) %>%
      mutate(
        T2m = as.numeric(T2m),
        WS = as.numeric(WS),
        pcp = as.numeric(pcp),
        Pressure = as.numeric(Pressure),
        Q2 = as.numeric(Q2)
      ) %>%
      filter(!is.na(valid_dttm), !is.na(SID))  # Filter out any rows with missing key values
  }, error = function(e) {
    cat("ERROR converting data:", e$message, "\n")
    return(NULL)
  })
  
  if (!is.null(obs_harp) && nrow(obs_harp) > 0) {
    # Write to SQLite
    cat("Writing to SQLite database\n")
    
    tryCatch({
      write_point_obs("Pressure", "Q2"),
        obs_harp,
        parameter = c("T2m", "WS10m", "Pcp"),
        obs_path = sqlite_dir,
        sqlite_file = "obstable_all"
      )
      cat("Observation data successfully written to SQLite database\n")
    }, error = function(e) {
      cat("ERROR writing to SQLite:", e$message, "\n")
    })
  } else {
    cat("No valid observation records after processing\n")
  }
} else {
  cat("No observation data found for the specified period\n")
}

cat("Observation processing completed\n")
