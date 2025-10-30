#################################################
## Convert observation CSV files to SQLite format
#################################################

# Load required libraries
suppressPackageStartupMessages({
  library(harpIO)
  library(dplyr)
  library(tibble)
  library(DBI)
  library(RSQLite)
})

# Custom function to read CSV observations in harp format
read_csv_obs <- function(file_name, dttm, parameter = NULL, ...) {
  
  # Read CSV data preserving datetime format - use read.csv for proper parsing
  obs_data <- read.csv(file_name, header = TRUE, stringsAsFactors = FALSE, 
                       na.strings = c("", "NA"))
  
  # Debug: print column names and first few rows
  cat("CSV columns:", paste(colnames(obs_data), collapse = ", "), "\n")
  cat("CSV dimensions:", nrow(obs_data), "rows,", ncol(obs_data), "columns\n")
  
  # Convert numeric columns safely
  numeric_cols <- c("SID", "lat", "lon", "elev", "T2m", "Td2m", "RH2m", "Q2m", 
                    "Pressure", "Wdir", "WS", "Pcp")
  existing_numeric_cols <- intersect(names(obs_data), numeric_cols)
  
  for (col in existing_numeric_cols) {
    obs_data[[col]] <- suppressWarnings(as.numeric(obs_data[[col]]))
  }
  
  # Map column names to harp conventions
  colname_mapping <- c("Pressure" = "Ps", "Wdir" = "D10m", "WS" = "S10m", "Pcp" = "AccPcp1h")
  
  for (old_name in names(colname_mapping)) {
    if (old_name %in% colnames(obs_data)) {
      colnames(obs_data)[colnames(obs_data) == old_name] <- colname_mapping[old_name]
    }
  }
  
  # Convert datetime to UNIX timestamp
  obs_data$valid_dttm <- as.numeric(as.POSIXct(obs_data$valid_dttm, tz = "UTC"))
  obs_data <- obs_data[!is.na(obs_data$valid_dttm), ]
  
  # Define all possible parameters with their metadata
  all_params <- list(
    T2m = list(accum_hours = 0, units = "degC"),
    Td2m = list(accum_hours = 0, units = "degC"),
    RH2m = list(accum_hours = 0, units = "%"),
    Q2m = list(accum_hours = 0, units = "kg/kg"),
    Ps = list(accum_hours = 0, units = "hPa"),
    D10m = list(accum_hours = 0, units = "degrees"),
    S10m = list(accum_hours = 0, units = "m/s"),
    AccPcp1h = list(accum_hours = 1, units = "mm")
  )
  
  # Filter to only include parameters that exist in the data
  available_params <- c()
  for (param in names(all_params)) {
    if (param %in% colnames(obs_data)) {
      available_params <- c(available_params, param)
    }
  }
  
  # Create parameter units dataframe for available parameters
  if (length(available_params) > 0) {
    obs_units <- data.frame(
      parameter = available_params,
      accum_hours = sapply(available_params, function(p) all_params[[p]]$accum_hours),
      units = sapply(available_params, function(p) all_params[[p]]$units),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  } else {
    stop("No valid parameters with data found in CSV file")
  }
  
  cat("Parameters found:", paste(obs_units$parameter, collapse = ", "), "\n")
  
  list(synop = obs_data, synop_params = obs_units)
}

# Main function
process_observations <- function(current_date) {
  if (nchar(current_date) != 10) {
    stop("Current date should be in yyyymmddHH format, E.g. 2023103100")
  }
  
  # Setup paths
  year <- substring(current_date, 1, 4)
  sqlite_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"
  
  # Ensure directory exists
  if (!dir.exists(sqlite_dir)) {
    dir.create(sqlite_dir, recursive = TRUE)
  }
  
  # Create datetime
  current_dttm <- ISOdatetime(
    as.numeric(substring(current_date, 1, 4)),
    as.numeric(substring(current_date, 5, 6)), 
    as.numeric(substring(current_date, 7, 8)),
    as.numeric(substring(current_date, 9, 10)), 0, 0, tz = "UTC"
  )
  
  # Process observations using harp
  result <- read_obs(
    dttm = current_dttm,
    parameter = NULL,
    file_format = "csv_obs",
    file_path = "/wrf/WRF_Model/Verification/Data/Obs",
    file_template = "local_obs{YYYY}{MM}{DD}{HH}00_verif.csv",
    return_data = TRUE
  )
  
  # Create SQLite database
  if (!is.null(result) && "synop" %in% names(result) && nrow(result$synop) > 0) {
    # Group observations by year and month
    result$synop$obs_year_month <- format(as.POSIXct(result$synop$valid_dttm, origin = "1970-01-01", tz = "UTC"), "%Y%m")
    obs_by_month <- split(result$synop, result$synop$obs_year_month)
    
    total_new_obs <- 0
    
    # Process each month separately
    for (obs_month in names(obs_by_month)) {
      month_obs <- obs_by_month[[obs_month]]
      month_obs$obs_year_month <- NULL  # Remove temporary column
      
      obstable_file <- file.path(sqlite_dir, paste0("obstable_", obs_month, ".sqlite"))
      con <- dbConnect(RSQLite::SQLite(), obstable_file)
      
      # Filter out existing observations
      new_obs <- month_obs
      if (dbExistsTable(con, "SYNOP")) {
        existing_obs <- dbReadTable(con, "SYNOP")
        existing_keys <- paste(as.character(existing_obs$SID), as.numeric(existing_obs$valid_dttm), sep = "_")
        new_keys <- paste(as.character(new_obs$SID), as.numeric(new_obs$valid_dttm), sep = "_")
        new_obs <- new_obs[!new_keys %in% existing_keys, ]
        cat("Existing:", nrow(existing_obs), "Before filtering:", nrow(month_obs), "After filtering:", nrow(new_obs), "\n")
      }
      
      # Write new observations and parameters
      if (nrow(new_obs) > 0) {
        dbWriteTable(con, "SYNOP", new_obs, append = TRUE)
        cat("Added", nrow(new_obs), "observations to", basename(obstable_file), "for month", obs_month, "\n")
        total_new_obs <- total_new_obs + nrow(new_obs)
      } else {
        cat("No new observations for month", obs_month, "\n")
      }
      
      # Always write/update SYNOP_params table
      if ("synop_params" %in% names(result) && nrow(result$synop_params) > 0) {
        dbWriteTable(con, "SYNOP_params", result$synop_params, overwrite = TRUE)
        cat("Updated SYNOP_params table with", nrow(result$synop_params), "parameters\n")
      }
      
      # Report database stats
      total_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM SYNOP")$count
      dbDisconnect(con)
      cat("SQLite file:", basename(obstable_file), "(", file.size(obstable_file), "bytes,", total_count, "observations)\n")
    }
    
    if (total_new_obs == 0) cat("No new observations added across all months\n")
  } else {
    stop("No data processed from observations")
  }
}

# Main execution
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: Rscript read_obs.R <YYYYMMDDHH>\nExample: Rscript read_obs.R 2023103100")
}

process_observations(args[1])