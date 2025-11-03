##################################################
# WRF Forecast Verification Script using harp
##################################################

# Load required libraries
suppressPackageStartupMessages({
  library(harp)
  library(dplyr)
  library(ggplot2)
  library(optparse)
  library(zoo)
  library(lubridate)
})

# Argument parsing and validation
parse_and_validate_args <- function() {
  option_list <- list(
    make_option(c("-s", "--start_date"), type="character", default=NULL, 
                help="Start date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-e", "--end_date"), type="character", default=NULL, 
                help="End date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-o", "--output_dir"), type="character", default="/wrf/WRF_Model/Verification/Results", 
                help="Output directory for verification results [default= %default]")
  )
  opt <- parse_args(OptionParser(option_list=option_list))
  if (is.null(opt$start_date) || is.null(opt$end_date) ||
      nchar(opt$start_date) != 10 || nchar(opt$end_date) != 10) {
    stop("Invalid start or end date. Must be in format YYYYMMDDHH.")
  }
  opt
}

# Moisture conversion functions
# Constants
Rd <- 287.05  # Gas constant for dry air (J/kg/K)
Rv <- 461.5   # Gas constant for water vapor (J/kg/K)
epsilon <- Rd / Rv  # ~0.622

# Calculate saturation vapor pressure (Bolton 1980)
calc_es <- function(t) {
  611.2 * exp(17.67 * (t - 273.15) / (t - 29.65))
}

# Convert specific humidity to relative humidity
calc_rh_from_q <- function(q, t, p) {
  es <- calc_es(t)
  e <- (q * p) / (epsilon + q * (1 - epsilon))
  rh <- 100 * e / es
  rh[rh < 0] <- 0
  rh[rh > 100] <- 100
  return(rh)
}

# Convert specific humidity to dew point temperature
calc_td_from_q <- function(q, t, p) {
  e <- (q * p) / (epsilon + q * (1 - epsilon))
  e[e <= 0] <- NA
  td <- 243.5 * log(e / 611.2) / (17.67 - log(e / 611.2)) + 273.15
  return(td)
}

# Convert dew point to relative humidity
calc_rh_from_td <- function(td, t) {
  e <- calc_es(td)
  es <- calc_es(t)
  rh <- 100 * e / es
  rh[rh < 0] <- 0
  rh[rh > 100] <- 100
  return(rh)
}

# Convert dew point to specific humidity
calc_q_from_td <- function(td, p) {
  e <- calc_es(td)
  q <- epsilon * e / (p - (1 - epsilon) * e)
  return(q)
}

# Convert relative humidity to dew point
calc_td_from_rh <- function(rh, t) {
  es <- calc_es(t)
  e <- (rh / 100) * es
  td <- 243.5 * log(e / 611.2) / (17.67 - log(e / 611.2)) + 273.15
  return(td)
}

# Convert relative humidity to specific humidity
calc_q_from_rh <- function(rh, t, p) {
  es <- calc_es(t)
  e <- (rh / 100) * es
  q <- epsilon * e / (p - (1 - epsilon) * e)
  return(q)
}

# Interpolate 3-hourly data to hourly for a single model dataframe
interpolate_to_hourly <- function(fcst_data, model_name = "unknown") {
  if (is.null(fcst_data) || !is.data.frame(fcst_data) || nrow(fcst_data) == 0) {
    return(fcst_data)
  }
  
  # Check if already hourly
  lead_times <- sort(unique(fcst_data$lead_time))
  if (length(lead_times) < 2) return(fcst_data)
  timestep <- median(diff(lead_times))
  if (timestep == 1) return(fcst_data)
  
  cat("  - Interpolating", model_name, "from", timestep, "hour to 1-hour timestep\n")
  
  # Store original classes to restore later
  orig_classes <- class(fcst_data)
  
  # Get forecast value column
  fcst_col <- names(fcst_data)[!(names(fcst_data) %in% 
    c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))]
  if (length(fcst_col) == 0) return(fcst_data)
  fcst_col <- fcst_col[1]
  
  # Interpolate for each station and forecast cycle
  result_list <- list()
  
  for (sid in unique(fcst_data$SID)) {
    for (fd in unique(fcst_data$fcst_dttm[fcst_data$SID == sid])) {
      subset_df <- fcst_data |> filter(SID == sid, fcst_dttm == fd) |> arrange(lead_time)
      
      if (nrow(subset_df) < 2) {
        result_list[[length(result_list) + 1]] <- subset_df
        next
      }
      
      # Create hourly sequence
      hourly_leads <- seq(min(subset_df$lead_time), max(subset_df$lead_time), by = 1)
      
      # Linear interpolation
      interpolated <- approx(
        x = subset_df$lead_time,
        y = subset_df[[fcst_col]],
        xout = hourly_leads,
        method = "linear",
        rule = 2
      )
      
      # Build result dataframe - preserve datetime types
      new_df <- data.frame(
        SID = sid,
        lead_time = hourly_leads,
        value = interpolated$y,
        stringsAsFactors = FALSE
      )
      names(new_df)[names(new_df) == "value"] <- fcst_col
      
      # Add datetime columns with correct type
      new_df$fcst_dttm <- as.POSIXct(fd, origin = "1970-01-01", tz = "UTC")
      new_df$valid_dttm <- new_df$fcst_dttm + lubridate::hours(hourly_leads)
      
      # Add metadata from original
      new_df$fcst_cycle <- subset_df$fcst_cycle[1]
      new_df$fcst_model <- subset_df$fcst_model[1]
      new_df$parameter <- subset_df$parameter[1]
      new_df$units <- subset_df$units[1]
      
      result_list[[length(result_list) + 1]] <- new_df
    }
  }
  
  result <- bind_rows(result_list)
  
  # Restore original class (harp_df if it was)
  class(result) <- orig_classes
  
  return(result)
}

# Forecast reading
read_forecasts <- function(start_date, end_date, wrf_models, gfs_model, fcst_dir) {
  cat("Step 1: Reading and processing forecasts...\n")
  leadtime_max <- as.numeric(Sys.getenv("LEADTIME"))
  
  # Read all models
  all_models <- c(wrf_models, gfs_model)
  params <- c("t2m", "psfc", "q2m", "ws10m", "pcp")
  
  # Store all forecast data by parameter
  all_fcst <- lapply(setNames(params, params), function(param) {
    cat("- Reading", param, "for all models...\n")
    
    # Read all models for this parameter
    fcst_list <- list()
    
    # Read WRF models (hourly)
    for (model in wrf_models) {
      cat("  - Reading", model, "(hourly)\n")
      fcst <- read_point_forecast(
        dttm = seq_dttm(start_date, end_date, "6h"),
        fcst_model = model,
        fcst_type = "det",
        parameter = param,
        file_path = fcst_dir,
        file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", param, "_{YYYY}{MM}_{HH}.sqlite"),
        lead_time = seq(0, leadtime_max, 1)
      )
      fcst_list[[model]] <- fcst
    }
    
    # Read GFS (3-hourly, needs interpolation)
    cat("  - Reading", gfs_model, "(3-hourly)\n")
    gfs_fcst <- read_point_forecast(
      dttm = seq_dttm(start_date, end_date, "6h"),
      fcst_model = gfs_model,
      fcst_type = "det",
      parameter = param,
      file_path = fcst_dir,
      file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", param, "_{YYYY}{MM}_{HH}.sqlite"),
      lead_time = seq(0, leadtime_max, 3)
    )
    
    # Interpolate GFS to hourly
    gfs_fcst_hourly <- interpolate_to_hourly(gfs_fcst, gfs_model)
    fcst_list[[gfs_model]] <- gfs_fcst_hourly
    
    # Return as harp_list
    as_harp_list(fcst_list)
  })
  
  return(all_fcst)
}

# Print forecast summary
print_forecast_summary <- function(fcst) {
  cat("\nForecast Data Summary:\n")
  for (param in names(fcst)) {
    cat("- Parameter:", param, "\n")
    for (model in names(fcst[[param]])) {
      cat("  - Model:", model, "\n")
      if (is.data.frame(fcst[[param]][[model]]) && nrow(fcst[[param]][[model]]) > 0) {
        cat("    - Data points:", nrow(fcst[[param]][[model]]), "\n")
      } else {
        cat("    - No valid data found\n")
      }
    }
  }
}

# Observation reading
read_observations <- function(fcst, obs_dir) {
  cat("Step 2: Reading observations...\n")
  
  # Helper function to read obs with error handling
  read_obs_safe <- function(param, desc = NULL) {
    tryCatch({
      obs <- read_point_obs(
        dttm = unique_valid_dttm(fcst$q2m),
        parameter = param,
        stations = unique_stations(fcst$q2m),
        obs_path = obs_dir,
        obsfile_template = "obstable_{YYYY}{MM}.sqlite"
      )
      if (!is.null(obs) && nrow(obs) > 0) {
        if (!is.null(desc)) cat("  - Found", desc, "observations\n")
        return(obs)
      }
      NULL
    }, error = function(e) NULL)
  }
  
  # Read standard observations
  obs_t2m <- read_point_obs(
    dttm = unique_valid_dttm(fcst$t2m),
    parameter = "T2m",
    stations = unique_stations(fcst$t2m),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_pressure <- read_point_obs(
    dttm = unique_valid_dttm(fcst$psfc),
    parameter = "Ps",
    stations = unique_stations(fcst$psfc),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_ws <- read_point_obs(
    dttm = unique_valid_dttm(fcst$ws10m),
    parameter = "S10m",
    stations = unique_stations(fcst$ws10m),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_pcp <- read_point_obs(
    dttm = unique_valid_dttm(fcst$pcp),
    parameter = "AccPcp1h",
    stations = unique_stations(fcst$pcp),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  
  # Try moisture parameters
  cat("- Checking available moisture parameters...\n")
  obs_td <- read_obs_safe("Td2m", "Td2m (dew point)")
  obs_rh <- read_obs_safe("RH2m", "RH2m (relative humidity)")
  obs_q <- read_obs_safe("Q2m", "Q2m (specific humidity)")
  
  if (is.null(obs_td) && is.null(obs_rh) && is.null(obs_q)) {
    cat("  - No moisture observations found (Td2m, RH2m, or Q2m)\n")
  }
  
  cat("- Observation T2m data points:", if(is.null(obs_t2m)) 0 else nrow(obs_t2m), "\n")
  cat("- Observation Pressure data points:", if(is.null(obs_pressure)) 0 else nrow(obs_pressure), "\n")
  cat("- Observation Wind Speed data points:", if(is.null(obs_ws)) 0 else nrow(obs_ws), "\n")
  cat("- Observation Precipitation data points:", if(is.null(obs_pcp)) 0 else nrow(obs_pcp), "\n")

  list(T2m = obs_t2m, Pressure = obs_pressure, Td2m = obs_td, RH2m = obs_rh, Q2m = obs_q, WindSpeed = obs_ws, AccPcp1h = obs_pcp)
}

# Calculate N-hour accumulated precipitation from 1-hour data
accumulate_precipitation <- function(fcst_1h_list, hours) {
  lapply(fcst_1h_list, function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    orig_class <- class(df)
    
    result <- df |>
      arrange(SID, fcst_dttm, valid_dttm) |>
      group_by(SID, fcst_dttm) |>
      mutate(
        fcst_accum = zoo::rollapply(fcst, width = hours, FUN = sum, align = "right", fill = NA, partial = FALSE)
      ) |>
      ungroup() |>
      filter(!is.na(fcst_accum)) |>
      select(SID, valid_dttm, lead_time, fcst_dttm, fcst_accum) |>
      rename(fcst = fcst_accum) |>
      mutate(parameter = paste0("AccPcp", hours, "h"), units = "mm")
    
    class(result) <- orig_class
    return(result)
  })
}

# Verify precipitation for a specific accumulation period
verify_pcp_period <- function(fcst_list, obs_1h, hours, output_dir) {
  param_name <- paste0("AccPcp", hours, "h")
  cat("  - Calculating", hours, "-hour accumulated precipitation...\n")
  
  # Calculate observed accumulation
  obs_accum <- obs_1h |>
    arrange(SID, valid_dttm) |>
    group_by(SID) |>
    mutate(
      accum = zoo::rollapply(AccPcp1h, width = hours, FUN = sum, align = "right", fill = NA, partial = FALSE)
    ) |>
    ungroup() |>
    filter(!is.na(accum)) |>
    select(valid_dttm, SID, lon, lat, elev, accum) |>
    mutate(units = "mm")
  
  names(obs_accum)[names(obs_accum) == "accum"] <- param_name
  
  if (length(fcst_list) == 0 || nrow(obs_accum) == 0) {
    cat("    - Insufficient data for", hours, "-hour verification\n")
    return(FALSE)
  }
  
  # Join and verify
  fcst_harp <- as_harp_list(fcst_list) |> set_units("mm") |> common_cases() |> join_to_fcst(obs_accum)
  
  # Filter NA values
  for (model in names(fcst_harp)) {
    if (is.data.frame(fcst_harp[[model]]) && nrow(fcst_harp[[model]]) > 0) {
      fcst_harp[[model]] <- fcst_harp[[model]] |> filter(!is.na(fcst) & !is.na(.data[[param_name]]))
    }
  }
  
  if (any(sapply(fcst_harp, function(x) is.data.frame(x) && nrow(x) > 0))) {
    verif <- det_verify(fcst_harp, !!sym(param_name))
    save_point_verif(verif, verif_path = file.path(output_dir))
    cat("    -", hours, "-hour precipitation verification saved\n")
    return(TRUE)
  }
  
  return(FALSE)
}

# Precipitation verification helper
verify_precipitation <- function(fcst_pcp, obs_pcp, output_dir) {
  if (is.null(obs_pcp) || nrow(obs_pcp) == 0) {
    cat("  - No precipitation observations available\n")
    return(FALSE)
  }
  
  # Convert total accumulated forecasts to 1-hour increments
  cat("  - Converting total accumulated forecasts to 1-hour increments...\n")
  
  fcst_1h_list <- lapply(names(fcst_pcp), function(model) {
    df <- fcst_pcp[[model]]
    if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) return(NULL)
    
    orig_class <- class(df)
    
    # Get forecast value column
    fcst_col <- names(df)[!(names(df) %in% c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))]
    if (length(fcst_col) == 0) return(NULL)
    fcst_col <- fcst_col[1]
    
    # Calculate 1-hour increments from total accumulation
    result <- df |>
      arrange(SID, fcst_dttm, lead_time) |>
      group_by(SID, fcst_dttm) |>
      mutate(
        pcp_1h = c(.data[[fcst_col]][1], diff(.data[[fcst_col]])),
        pcp_1h = ifelse(pcp_1h < 0, .data[[fcst_col]], pcp_1h)  # Handle resets
      ) |>
      ungroup() |>
      select(SID, valid_dttm, lead_time, fcst_dttm, pcp_1h) |>
      rename(fcst = pcp_1h) |>
      mutate(parameter = "AccPcp1h", units = "mm")
    
    class(result) <- orig_class
    return(result)
  })
  names(fcst_1h_list) <- names(fcst_pcp)
  fcst_1h_list <- fcst_1h_list[!sapply(fcst_1h_list, is.null)]
  
  if (length(fcst_1h_list) == 0) {
    cat("  - No valid precipitation forecast data\n")
    return(FALSE)
  }
  
  # Verify 1-hour precipitation
  cat("  - Verifying 1-hour accumulated precipitation...\n")
  valid_1h <- verify_pcp_period(fcst_1h_list, obs_pcp, 1, output_dir)
  
  # Calculate and verify 12-hour accumulation
  fcst_12h_list <- accumulate_precipitation(fcst_1h_list, 12)
  names(fcst_12h_list) <- names(fcst_1h_list)
  fcst_12h_list <- fcst_12h_list[!sapply(fcst_12h_list, is.null)]
  valid_12h <- verify_pcp_period(fcst_12h_list, obs_pcp, 12, output_dir)
  
  # Calculate and verify 24-hour accumulation
  fcst_24h_list <- accumulate_precipitation(fcst_1h_list, 24)
  names(fcst_24h_list) <- names(fcst_1h_list)
  fcst_24h_list <- fcst_24h_list[!sapply(fcst_24h_list, is.null)]
  valid_24h <- verify_pcp_period(fcst_24h_list, obs_pcp, 24, output_dir)
  
  return(valid_1h || valid_12h || valid_24h)
}

# Verification workflow
verify_and_save <- function(fcst, obs, output_dir) {
  cat("Step 3: Processing and verifying...\n")
  
  # Helper function to verify and save single parameter
  verify_param <- function(data, obs_data, obs_param, param_name) {
    if (any(sapply(data, function(x) is.data.frame(x) && nrow(x) > 0))) {
      verif <- det_verify(data, !!sym(obs_param))
      save_point_verif(verif, verif_path = file.path(output_dir))
      cat("-", param_name, "verification saved.\n")
      return(TRUE)
    }
    cat("No valid forecast-observation pairs for", tolower(param_name), ".\n")
    return(FALSE)
  }
  
  # Temperature
  valid_t2m <- verify_param(
    fcst$t2m |> scale_param(-273.15, "degC") |> common_cases() |> join_to_fcst(obs$T2m),
    obs$T2m, "T2m", "Temperature"
  )
  
  # Pressure
  valid_psfc <- verify_param(
    scale_param(fcst$psfc, 0.01, "hPa", mult = TRUE) |> common_cases() |> join_to_fcst(obs$Pressure),
    obs$Pressure, "Ps", "Pressure"
  )
  
  # Moisture verification
  valid_moisture <- verify_moisture(fcst, obs, output_dir)
  
  # Wind Speed
  valid_ws <- verify_param(
    fcst$ws10m |> set_units("m/s") |> common_cases() |> join_to_fcst(obs$WindSpeed),
    obs$WindSpeed, "S10m", "Wind Speed"
  )

  # Precipitation verification
  cat("- Processing precipitation...\n")
  valid_pcp <- verify_precipitation(fcst$pcp, obs$AccPcp1h, output_dir)
  
  if (!valid_t2m && !valid_psfc && !valid_moisture && !valid_ws && !valid_pcp) {
    cat("No valid forecast-observation pairs found after joining. Exiting.\n")
    quit(status = 1)
  }
}

# Moisture verification helper
verify_moisture <- function(fcst, obs, output_dir) {
  cat("- Processing moisture parameters...\n")
  
  # Prepare merged moisture data
  fcst_moisture <- lapply(names(fcst$q2m), function(model) {
    q2m_df <- fcst$q2m[[model]]
    t2m_df <- fcst$t2m[[model]]
    psfc_df <- fcst$psfc[[model]]
    
    if (!is.data.frame(q2m_df) || !is.data.frame(t2m_df) || !is.data.frame(psfc_df) ||
        nrow(q2m_df) == 0 || nrow(t2m_df) == 0 || nrow(psfc_df) == 0) return(NULL)
    
    # Find forecast value columns - exclude metadata
    get_fcst_col <- function(df) {
      cols <- names(df)[!(names(df) %in% c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))]
      if (length(cols) == 0) return(NULL)
      cols[1]
    }
    
    q2m_col <- get_fcst_col(q2m_df)
    t2m_col <- get_fcst_col(t2m_df)
    psfc_col <- get_fcst_col(psfc_df)
    
    if (is.null(q2m_col) || is.null(t2m_col) || is.null(psfc_col)) {
      cat("  - Warning: Could not find forecast columns for model", model, "\n")
      return(NULL)
    }
    
    # Merge dataframes
    q2m_df |>
      select(SID, valid_dttm, lead_time, fcst_dttm, q2m_val = all_of(q2m_col)) |>
      inner_join(t2m_df |> select(SID, valid_dttm, lead_time, fcst_dttm, t2m_val = all_of(t2m_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")) |>
      inner_join(psfc_df |> select(SID, valid_dttm, lead_time, fcst_dttm, psfc_val = all_of(psfc_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm"))
  })
  names(fcst_moisture) <- names(fcst$q2m)
  
  if (!any(sapply(fcst_moisture, function(x) !is.null(x) && nrow(x) > 0))) {
    cat("  - No valid forecast moisture data available.\n")
    return(FALSE)
  }
  
  # Complete observations: calculate missing moisture parameters from available ones
  obs_complete <- complete_moisture_obs(obs, fcst_moisture)
  
  # Verify all three moisture parameters
  valid_td <- verify_moisture_param(fcst_moisture, obs_complete$Td2m, "Td2m", "Dew Point Temperature", 
                                     calc_td_from_q, "degC", -273.15, output_dir)
  valid_rh <- verify_moisture_param(fcst_moisture, obs_complete$RH2m, "RH2m", "Relative Humidity",
                                     calc_rh_from_q, "percent", 0, output_dir)
  valid_q <- verify_moisture_param(fcst_moisture, obs_complete$Q2m, "Q2m", "Specific Humidity",
                                    NULL, "kg/kg", 0, output_dir)
  
  if (!valid_td && !valid_rh && !valid_q) {
    cat("  - No valid forecast-observation pairs for any moisture parameter.\n")
    return(FALSE)
  }
  return(TRUE)
}

# Complete moisture observations by calculating missing parameters
complete_moisture_obs <- function(obs, fcst_moisture) {
  cat("- Completing moisture observations...\n")
  
  # Check what's available
  has_td <- !is.null(obs$Td2m) && nrow(obs$Td2m) > 0
  has_rh <- !is.null(obs$RH2m) && nrow(obs$RH2m) > 0
  has_q <- !is.null(obs$Q2m) && nrow(obs$Q2m) > 0
  
  if (!has_td && !has_rh && !has_q) {
    cat("  - No moisture observations available to complete.\n")
    return(list(Td2m = NULL, RH2m = NULL, Q2m = NULL))
  }
  
  # Get t2m and psfc observations for conversions
  obs_t2m <- obs$T2m
  obs_ps <- obs$Pressure
  
  # Start with what we have
  obs_td <- obs$Td2m
  obs_rh_out <- obs$RH2m
  obs_q_out <- obs$Q2m
  
  # Calculate missing parameters based on what's available
  if (has_td) {
    cat("  - Using Td2m observations as base\n")
    
    if (!has_q && !is.null(obs_ps)) {
      cat("    - Calculating Q2m from Td2m\n")
      obs_q_out <- obs_td |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_td(Td2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
    
    if (!has_rh && !is.null(obs_t2m)) {
      cat("    - Calculating RH2m from Td2m\n")
      obs_rh_out <- obs_td |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_td(Td2m, T2m), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  if (has_rh && !is.null(obs_t2m)) {
    cat("  - Using RH2m observations for calculations\n")
    
    if (!has_td) {
      cat("    - Calculating Td2m from RH2m\n")
      obs_td <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_rh(RH2m, T2m), units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    
    if (!has_q && !is.null(obs_ps)) {
      cat("    - Calculating Q2m from RH2m\n")
      obs_q_out <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_rh(RH2m, T2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
  }
  
  if (has_q && !is.null(obs_t2m) && !is.null(obs_ps)) {
    cat("  - Using Q2m observations for calculations\n")
    
    if (!has_td) {
      cat("    - Calculating Td2m from Q2m\n")
      obs_td <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_q(Q2m, T2m, Ps) - 273.15, units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    
    if (!has_rh) {
      cat("    - Calculating RH2m from Q2m\n")
      obs_rh_out <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_q(Q2m, T2m, Ps), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  list(Td2m = obs_td, RH2m = obs_rh_out, Q2m = obs_q_out)
}

# Moisture parameter verification
verify_moisture_param <- function(fcst_moisture, obs_data, param, param_desc, 
                                   calc_func, units, offset, output_dir) {
  if (is.null(obs_data) || nrow(obs_data) == 0) return(FALSE)
  
  cat("  - Verifying", param_desc, paste0("(", param, ")...\n"))
  
  fcst_list <- lapply(fcst_moisture, function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    if (!is.null(calc_func)) {
      # Calculate derived parameter
      q_vals <- as.numeric(df$q2m_val)
      t_vals <- as.numeric(df$t2m_val)
      p_vals <- as.numeric(df$psfc_val)
      
      df$fcst <- calc_func(q_vals, t_vals, p_vals) + offset
    } else {
      # Use q2m directly
      df$fcst <- df$q2m_val
    }
    
    df$parameter <- param
    df$units <- units
    result <- df |> select(SID, valid_dttm, lead_time, fcst_dttm, parameter, fcst, units)
    return(result)
  })
  names(fcst_list) <- names(fcst_moisture)
  
  # Standardize observation units to match forecast
  if (!is.null(obs_data) && "units" %in% names(obs_data)) {
    # Handle relative humidity unit variants (% vs percent)
    if (units == "percent" && any(obs_data$units == "%")) {
      obs_data$units <- "percent"
    }
  }
  
  cat("  - Creating harp_list and joining...\n")
  cat("  - Observation rows:", nrow(obs_data), "\n")
  if (nrow(obs_data) > 0) {
    cat("  - Obs columns:", paste(names(obs_data), collapse=", "), "\n")
    cat("  - Obs valid_dttm range: [", min(obs_data$valid_dttm, na.rm=TRUE), ",", max(obs_data$valid_dttm, na.rm=TRUE), "]\n")
  }
  
  fcst_list <- as_harp_list(fcst_list) |> set_units(units) |> common_cases() |> join_to_fcst(obs_data)

  # Filter out rows with NA in forecast or observation value to avoid plotting/binning errors
  for (model_name in names(fcst_list)) {
    model_data <- fcst_list[[model_name]]
    if (is.data.frame(model_data) && nrow(model_data) > 0) {
      # If the observation column exists (param), remove rows where it's NA; always remove NA fcst
      if (param %in% names(model_data)) {
        model_data <- model_data |> filter(!is.na(fcst) & !is.na(.data[[param]]))
      } else {
        model_data <- model_data |> filter(!is.na(fcst))
      }
      fcst_list[[model_name]] <- model_data
    }
  }

  # Debug: Check joined data after NA filtering
  for (model_name in names(fcst_list)) {
    model_data <- fcst_list[[model_name]]
    if (is.data.frame(model_data)) {
      cat("  - Model", model_name, "after join+filter: rows =", nrow(model_data), "\n")
      if (nrow(model_data) > 0) {
        cat("    - Columns:", paste(names(model_data), collapse=", "), "\n")
      }
    }
  }
  
  # If no model has rows after filtering, skip verification
  if (!any(sapply(fcst_list, function(x) is.data.frame(x) && nrow(x) > 0))) {
    cat("  - No valid pairs found after join+filter\n")
    return(FALSE)
  }

  # Run det_verify
  verif <- tryCatch({
    det_verify(fcst_list, !!sym(param))
  }, error = function(e) {
    cat("  - det_verify error for", param, ":", e$message, "\n")
    return(NULL)
  })

  if (is.null(verif)) {
    cat("  -", param_desc, "verification skipped due to det_verify error.\n")
    return(FALSE)
  }

  save_point_verif(verif, verif_path = file.path(output_dir))
  cat("  -", param_desc, "verification saved.\n")
  return(TRUE)
}

# Main script
opt <- parse_and_validate_args()
cat("Starting verification for:", opt$start_date, "to", opt$end_date, "- Models: WRF (d01 & d02) and GFS\n")
cat("Parameters: Temperature, Pressure, Moisture (Td/RH/Q), Wind Speed, Precipitation\n")
cat("Note: GFS data interpolated from 3-hourly to 1-hourly for uniform processing\n")
cat("Note: Precipitation verified at 1h, 12h, and 24h accumulation periods\n")
wrf_models <- c("wrf_d01", "wrf_d02")
gfs_model <- "gfs"
fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

fcst <- read_forecasts(opt$start_date, opt$end_date, wrf_models, gfs_model, fcst_dir)
print_forecast_summary(fcst)
obs <- read_observations(fcst, obs_dir)

cat("\n=== Forecast/observation time alignment check ===\n")

for (m in names(fcst$t2m)) {
  cat("Model:", m, "\n")
  tmp <- fcst$t2m[[m]]
  if (!is.null(tmp) && nrow(tmp) > 0) {
    print(range(tmp$valid_dttm))
    cat("Unique lead times:", paste(sort(unique(tmp$lead_time)), collapse = ", "), "\n")
  }
}

cat("\nObservation valid_dttm range:\n")
if (!is.null(obs$T2m) && nrow(obs$T2m) > 0) {
  print(range(obs$T2m$valid_dttm))
  cat("Observation time step (hours):",
      median(diff(sort(unique(obs$T2m$valid_dttm))) / 3600), "\n")
} else {
  cat("No T2m observations available to compute time range or step.\n")
}

# Run verification
verify_and_save(fcst, obs, opt$output_dir)

