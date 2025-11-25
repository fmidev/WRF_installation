# Forecast Verification Script using harp

# Load required libraries
suppressPackageStartupMessages({
  library(harp)
  library(dplyr)
  library(ggplot2)
  library(optparse)
  library(zoo)
  library(lubridate)
})

# Parse and validate command-line arguments
parse_and_validate_args <- function() {
  option_list <- list(
    make_option(c("-s", "--start_date"), type="character", default=NULL, 
                help="Start date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-e", "--end_date"), type="character", default=NULL, 
                help="End date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-o", "--output_dir"), type="character", default="/wrf/WRF_Model/Verification/Results", 
                help="Output directory for verification results [default= %default]"),
    make_option(c("-d", "--subdir"), type="character", default=NULL,
                help="Subdirectory name under output_dir for this verification run [default= start_date-end_date]"),
    make_option(c("-m", "--hourly_models"), type="character", default="wrf_d01,wrf_d02",
                help="Comma-separated list of hourly models [default= %default]"),
    make_option(c("-n", "--multihourly_models"), type="character", default="gfs",
                help="Comma-separated list of 3-hourly models [default= %default]")
  )
  opt <- parse_args(OptionParser(option_list=option_list))
  if (is.null(opt$start_date) || is.null(opt$end_date) ||
      nchar(opt$start_date) != 10 || nchar(opt$end_date) != 10) {
    stop("Invalid start or end date. Must be in format YYYYMMDDHH.")
  }
  
  opt$hourly_models <- if (nchar(opt$hourly_models) > 0) strsplit(opt$hourly_models, ",")[[1]] else character(0)
  opt$multihourly_models <- if (nchar(opt$multihourly_models) > 0) strsplit(opt$multihourly_models, ",")[[1]] else character(0)
  
  # Create subdirectory name if not provided
  if (is.null(opt$subdir) || nchar(opt$subdir) == 0) {
    opt$subdir <- paste0(opt$start_date, "-", opt$end_date)
  }
  
  # Create full output path with subdirectory
  opt$output_dir <- file.path(opt$output_dir, opt$subdir)
  
  # Create directory if it doesn't exist
  if (!dir.exists(opt$output_dir)) {
    dir.create(opt$output_dir, recursive = TRUE)
    cat("Created output directory:", opt$output_dir, "\n")
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

# Interpolate 3-hourly data to hourly
interpolate_to_hourly <- function(fcst_data, model_name = "unknown") {
  if (is.null(fcst_data) || !is.data.frame(fcst_data) || nrow(fcst_data) == 0) return(fcst_data)
  
  lead_times <- sort(unique(fcst_data$lead_time))
  if (length(lead_times) < 2) return(fcst_data)
  timestep <- median(diff(lead_times))
  if (timestep == 1) return(fcst_data)
  
  cat("  - Interpolating", model_name, "from", timestep, "hour to 1-hour timestep\n")
  
  orig_classes <- class(fcst_data)
  fcst_col <- names(fcst_data)[!(names(fcst_data) %in% 
    c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))][1]
  if (is.na(fcst_col)) return(fcst_data)
  
  result_list <- list()
  for (sid in unique(fcst_data$SID)) {
    for (fd in unique(fcst_data$fcst_dttm[fcst_data$SID == sid])) {
      subset_df <- fcst_data |> filter(SID == sid, fcst_dttm == fd) |> arrange(lead_time)
      if (nrow(subset_df) < 2) {
        result_list[[length(result_list) + 1]] <- subset_df
        next
      }
      
      hourly_leads <- seq(min(subset_df$lead_time), max(subset_df$lead_time), by = 1)
      interpolated <- approx(x = subset_df$lead_time, y = subset_df[[fcst_col]], 
                             xout = hourly_leads, method = "linear", rule = 2)
      
      new_df <- data.frame(SID = sid, lead_time = hourly_leads, value = interpolated$y, stringsAsFactors = FALSE)
      names(new_df)[names(new_df) == "value"] <- fcst_col
      new_df$fcst_dttm <- as.POSIXct(fd, origin = "1970-01-01", tz = "UTC")
      new_df$valid_dttm <- new_df$fcst_dttm + lubridate::hours(hourly_leads)
      new_df$fcst_cycle <- subset_df$fcst_cycle[1]
      new_df$fcst_model <- subset_df$fcst_model[1]
      new_df$parameter <- subset_df$parameter[1]
      new_df$units <- subset_df$units[1]
      result_list[[length(result_list) + 1]] <- new_df
    }
  }
  
  result <- bind_rows(result_list)
  class(result) <- orig_classes
  return(result)
}

# Read forecasts for all models
read_forecasts <- function(start_date, end_date, hourly_models, multihourly_models, fcst_dir) {
  cat("Step 1: Reading and processing forecasts...\n")
  leadtime_max <- as.numeric(Sys.getenv("LEADTIME"))
  params <- c("t2m", "psfc", "q2m", "ws10m", "pcp")
  
  all_fcst <- lapply(setNames(params, params), function(param) {
    cat("- Reading", param, "for all models...\n")
    fcst_list <- list()
    
    for (model in hourly_models) {
      cat("  - Reading", model, "(hourly)\n")
      fcst_list[[model]] <- read_point_forecast(
        dttm = seq_dttm(start_date, end_date, "6h"), fcst_model = model, fcst_type = "det",
        parameter = param, file_path = fcst_dir,
        file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", param, "_{YYYY}{MM}_{HH}.sqlite"),
        lead_time = seq(0, leadtime_max, 1)
      )
    }
    
    for (model in multihourly_models) {
      cat("  - Reading", model, "(3-hourly)\n")
      fcst <- read_point_forecast(
        dttm = seq_dttm(start_date, end_date, "6h"), fcst_model = model, fcst_type = "det",
        parameter = param, file_path = fcst_dir,
        file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", param, "_{YYYY}{MM}_{HH}.sqlite"),
        lead_time = seq(0, leadtime_max, 3)
      )
      fcst_list[[model]] <- interpolate_to_hourly(fcst, model)
    }
    
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
      n_rows <- if (is.data.frame(fcst[[param]][[model]])) nrow(fcst[[param]][[model]]) else 0
      cat("  - Model:", model, "-", n_rows, "data points\n")
    }
  }
}

# Read observations
read_observations <- function(fcst, obs_dir) {
  cat("Step 2: Reading observations...\n")
  
  read_obs_safe <- function(param, dttm, stations) {
    tryCatch({
      obs <- read_point_obs(dttm = dttm, parameter = param, stations = stations,
                            obs_path = obs_dir, obsfile_template = "obstable_{YYYY}{MM}.sqlite")
      if (!is.null(obs) && nrow(obs) > 0) return(obs)
      NULL
    }, error = function(e) NULL)
  }
  
  obs_t2m <- read_obs_safe("T2m", unique_valid_dttm(fcst$t2m), unique_stations(fcst$t2m))
  obs_pressure <- read_obs_safe("Ps", unique_valid_dttm(fcst$psfc), unique_stations(fcst$psfc))
  obs_ws <- read_obs_safe("S10m", unique_valid_dttm(fcst$ws10m), unique_stations(fcst$ws10m))
  obs_pcp <- read_obs_safe("AccPcp1h", unique_valid_dttm(fcst$pcp), unique_stations(fcst$pcp))
  
  cat("- Checking moisture parameters...\n")
  obs_td <- read_obs_safe("Td2m", unique_valid_dttm(fcst$q2m), unique_stations(fcst$q2m))
  obs_rh <- read_obs_safe("RH2m", unique_valid_dttm(fcst$q2m), unique_stations(fcst$q2m))
  obs_q <- read_obs_safe("Q2m", unique_valid_dttm(fcst$q2m), unique_stations(fcst$q2m))
  
  if (!is.null(obs_td)) cat("  - Found Td2m\n")
  if (!is.null(obs_rh)) cat("  - Found RH2m\n")
  if (!is.null(obs_q)) cat("  - Found Q2m\n")
  if (is.null(obs_td) && is.null(obs_rh) && is.null(obs_q)) {
    cat("  - No moisture observations found\n")
  }
  
  cat("- T2m:", if(is.null(obs_t2m)) 0 else nrow(obs_t2m), "points\n")
  cat("- Pressure:", if(is.null(obs_pressure)) 0 else nrow(obs_pressure), "points\n")
  cat("- Wind Speed:", if(is.null(obs_ws)) 0 else nrow(obs_ws), "points\n")
  cat("- Precipitation:", if(is.null(obs_pcp)) 0 else nrow(obs_pcp), "points\n")

  list(T2m = obs_t2m, Pressure = obs_pressure, Td2m = obs_td, RH2m = obs_rh, Q2m = obs_q, WindSpeed = obs_ws, AccPcp1h = obs_pcp)
}

# Calculate N-hour accumulated precipitation
accumulate_precipitation <- function(fcst_1h_list, hours) {
  lapply(fcst_1h_list, function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    orig_class <- class(df)
    result <- df |>
      arrange(SID, fcst_dttm, valid_dttm) |>
      group_by(SID, fcst_dttm) |>
      mutate(fcst_accum = zoo::rollapply(fcst, width = hours, FUN = sum, align = "right", fill = NA, partial = FALSE)) |>
      ungroup() |>
      filter(!is.na(fcst_accum)) |>
      select(SID, valid_dttm, lead_time, fcst_dttm, fcst_accum) |>
      rename(fcst = fcst_accum) |>
      mutate(parameter = paste0("AccPcp", hours, "h"), units = "mm")
    class(result) <- orig_class
    return(result)
  })
}

# Verify precipitation for specific accumulation period
verify_pcp_period <- function(fcst_list, obs_1h, hours, output_dir) {
  param_name <- paste0("AccPcp", hours, "h")
  cat("  - Verifying", hours, "-hour accumulation...\n")
  
  obs_accum <- obs_1h |>
    arrange(SID, valid_dttm) |>
    group_by(SID) |>
    mutate(accum = zoo::rollapply(AccPcp1h, width = hours, FUN = sum, align = "right", fill = NA, partial = FALSE)) |>
    ungroup() |>
    filter(!is.na(accum)) |>
    select(valid_dttm, SID, lon, lat, elev, accum) |>
    mutate(units = "mm")
  names(obs_accum)[names(obs_accum) == "accum"] <- param_name
  
  if (length(fcst_list) == 0 || nrow(obs_accum) == 0) return(FALSE)
  
  fcst_harp <- as_harp_list(fcst_list) |> set_units("mm") |> common_cases() |> join_to_fcst(obs_accum)
  
  for (model in names(fcst_harp)) {
    if (is.data.frame(fcst_harp[[model]]) && nrow(fcst_harp[[model]]) > 0) {
      fcst_harp[[model]] <- fcst_harp[[model]] |> filter(!is.na(fcst) & !is.na(.data[[param_name]]))
    }
  }
  
  if (any(sapply(fcst_harp, function(x) is.data.frame(x) && nrow(x) > 0))) {
    verif <- det_verify(fcst_harp, !!sym(param_name))
    save_point_verif(verif, verif_path = file.path(output_dir))
    cat("    - Saved\n")
    return(TRUE)
  }
  return(FALSE)
}

# Verify precipitation
verify_precipitation <- function(fcst_pcp, obs_pcp, output_dir, start_date, end_date) {
  if (is.null(obs_pcp) || nrow(obs_pcp) == 0) {
    cat("  - No precipitation observations\n")
    return(FALSE)
  }
  
  start_dt <- as.POSIXct(start_date, format = "%Y%m%d%H", tz = "UTC")
  end_dt <- as.POSIXct(end_date, format = "%Y%m%d%H", tz = "UTC")
  period_days <- as.numeric(difftime(end_dt, start_dt, units = "days"))
  cat("  - Period:", round(period_days, 1), "days\n")
  
  cat("  - Converting to 1-hour increments...\n")
  fcst_1h_list <- lapply(names(fcst_pcp), function(model) {
    df <- fcst_pcp[[model]]
    if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) return(NULL)
    orig_class <- class(df)
    fcst_col <- names(df)[!(names(df) %in% c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))][1]
    if (is.na(fcst_col)) return(NULL)
    
    result <- df |>
      arrange(SID, fcst_dttm, lead_time) |>
      group_by(SID, fcst_dttm) |>
      mutate(pcp_1h = c(.data[[fcst_col]][1], diff(.data[[fcst_col]])),
             pcp_1h = ifelse(pcp_1h < 0, .data[[fcst_col]], pcp_1h)) |>
      ungroup() |>
      select(SID, valid_dttm, lead_time, fcst_dttm, pcp_1h) |>
      rename(fcst = pcp_1h) |>
      mutate(parameter = "AccPcp1h", units = "mm")
    class(result) <- orig_class
    return(result)
  })
  names(fcst_1h_list) <- names(fcst_pcp)
  fcst_1h_list <- fcst_1h_list[!sapply(fcst_1h_list, is.null)]
  
  if (length(fcst_1h_list) == 0) return(FALSE)
  
  valid_1h <- verify_pcp_period(fcst_1h_list, obs_pcp, 1, output_dir)
  
  valid_12h <- FALSE
  valid_24h <- FALSE
  if (period_days > 3) {
    cat("  - Including 12h and 24h accumulation\n")
    fcst_12h_list <- accumulate_precipitation(fcst_1h_list, 12)
    names(fcst_12h_list) <- names(fcst_1h_list)
    valid_12h <- verify_pcp_period(fcst_12h_list[!sapply(fcst_12h_list, is.null)], obs_pcp, 12, output_dir)
    
    fcst_24h_list <- accumulate_precipitation(fcst_1h_list, 24)
    names(fcst_24h_list) <- names(fcst_1h_list)
    valid_24h <- verify_pcp_period(fcst_24h_list[!sapply(fcst_24h_list, is.null)], obs_pcp, 24, output_dir)
  }
  
  return(valid_1h || valid_12h || valid_24h)
}

# Verify simple parameter
verify_simple_param <- function(fcst_data, obs_data, obs_param, param_name, preprocess_func = NULL, output_dir) {
  cat("- Verifying", param_name, "...\n")
  if (!is.null(preprocess_func)) fcst_data <- preprocess_func(fcst_data)
  fcst_joined <- fcst_data |> common_cases() |> join_to_fcst(obs_data)
  
  if (any(sapply(fcst_joined, function(x) is.data.frame(x) && nrow(x) > 0))) {
    verif <- det_verify(fcst_joined, !!sym(obs_param))
    save_point_verif(verif, verif_path = file.path(output_dir))
    cat("  - Saved\n")
    return(list(success = TRUE, data = fcst_joined))
  }
  cat("  - No valid pairs\n")
  return(list(success = FALSE, data = NULL))
}

# Run all verifications
verify_and_save <- function(fcst, obs, output_dir, start_date, end_date) {
  cat("Step 3: Processing and verifying...\n")
  
  verif_tasks <- list(
    list(name = "Temperature", fcst_data = fcst$t2m, obs_data = obs$T2m, obs_param = "T2m",
         preprocess = function(x) scale_param(x, -273.15, "degC")),
    list(name = "Pressure", fcst_data = fcst$psfc, obs_data = obs$Pressure, obs_param = "Ps",
         preprocess = function(x) scale_param(x, 0.01, "hPa", mult = TRUE)),
    list(name = "Wind Speed", fcst_data = fcst$ws10m, obs_data = obs$WindSpeed, obs_param = "S10m",
         preprocess = function(x) set_units(x, "m/s"))
  )
  
  valid_results <- sapply(verif_tasks, function(task) {
    result <- verify_simple_param(task$fcst_data, task$obs_data, task$obs_param, task$name, task$preprocess, output_dir)
    return(result$success)
  })
  
  valid_moisture <- verify_moisture(fcst, obs, output_dir)
  
  cat("- Processing precipitation...\n")
  valid_pcp <- verify_precipitation(fcst$pcp, obs$AccPcp1h, output_dir, start_date, end_date)
  
  if (!any(valid_results) && !valid_moisture && !valid_pcp) {
    cat("No valid forecast-observation pairs found. Exiting.\n")
    quit(status = 1)
  }
}

# Extract forecast column from dataframe
get_fcst_col <- function(df) {
  cols <- names(df)[!(names(df) %in% c("SID", "valid_dttm", "lead_time", "fcst_dttm", 
                                        "fcst_cycle", "units", "fcst_model", "parameter", "z"))]
  if (length(cols) == 0) return(NULL)
  cols[1]
}

# Prepare merged moisture forecast data
prepare_moisture_fcst <- function(fcst) {
  lapply(names(fcst$q2m), function(model) {
    q2m_df <- fcst$q2m[[model]]
    t2m_df <- fcst$t2m[[model]]
    psfc_df <- fcst$psfc[[model]]
    
    if (!is.data.frame(q2m_df) || !is.data.frame(t2m_df) || !is.data.frame(psfc_df) ||
        nrow(q2m_df) == 0 || nrow(t2m_df) == 0 || nrow(psfc_df) == 0) return(NULL)
    
    q2m_col <- get_fcst_col(q2m_df)
    t2m_col <- get_fcst_col(t2m_df)
    psfc_col <- get_fcst_col(psfc_df)
    
    if (is.null(q2m_col) || is.null(t2m_col) || is.null(psfc_col)) return(NULL)
    
    q2m_df |>
      select(SID, valid_dttm, lead_time, fcst_dttm, q2m_val = all_of(q2m_col)) |>
      inner_join(t2m_df |> select(SID, valid_dttm, lead_time, fcst_dttm, t2m_val = all_of(t2m_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")) |>
      inner_join(psfc_df |> select(SID, valid_dttm, lead_time, fcst_dttm, psfc_val = all_of(psfc_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm"))
  })
}

# Verify moisture parameters
verify_moisture <- function(fcst, obs, output_dir) {
  cat("- Processing moisture...\n")
  
  fcst_moisture <- prepare_moisture_fcst(fcst)
  names(fcst_moisture) <- names(fcst$q2m)
  
  if (!any(sapply(fcst_moisture, function(x) !is.null(x) && nrow(x) > 0))) {
    cat("  - No valid forecast data\n")
    return(FALSE)
  }
  
  obs_complete <- complete_moisture_obs(obs, fcst_moisture)
  
  moisture_params <- list(
    list(param = "Td2m", desc = "Dew Point", calc_func = calc_td_from_q, units = "degC", offset = -273.15),
    list(param = "RH2m", desc = "Relative Humidity", calc_func = calc_rh_from_q, units = "percent", offset = 0),
    list(param = "Q2m", desc = "Specific Humidity", calc_func = NULL, units = "kg/kg", offset = 0)
  )
  
  valid_results <- sapply(moisture_params, function(mp) {
    verify_moisture_param(fcst_moisture, obs_complete[[mp$param]], mp$param, mp$desc, 
                          mp$calc_func, mp$units, mp$offset, output_dir)
  })
  
  if (!any(valid_results)) {
    cat("  - No valid pairs\n")
    return(FALSE)
  }
  return(TRUE)
}

# Complete moisture observations by calculating missing parameters
complete_moisture_obs <- function(obs, fcst_moisture) {
  cat("  - Completing moisture observations\n")
  
  has_td <- !is.null(obs$Td2m) && nrow(obs$Td2m) > 0
  has_rh <- !is.null(obs$RH2m) && nrow(obs$RH2m) > 0
  has_q <- !is.null(obs$Q2m) && nrow(obs$Q2m) > 0
  
  if (!has_td && !has_rh && !has_q) return(list(Td2m = NULL, RH2m = NULL, Q2m = NULL))
  
  obs_t2m <- obs$T2m
  obs_ps <- obs$Pressure
  obs_td <- obs$Td2m
  obs_rh_out <- obs$RH2m
  obs_q_out <- obs$Q2m
  
  if (has_td) {
    if (!has_q && !is.null(obs_ps)) {
      obs_q_out <- obs_td |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_td(Td2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
    if (!has_rh && !is.null(obs_t2m)) {
      obs_rh_out <- obs_td |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_td(Td2m, T2m), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  if (has_rh && !is.null(obs_t2m)) {
    if (!has_td) {
      obs_td <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_rh(RH2m, T2m), units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    if (!has_q && !is.null(obs_ps)) {
      obs_q_out <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_rh(RH2m, T2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
  }
  
  if (has_q && !is.null(obs_t2m) && !is.null(obs_ps)) {
    if (!has_td) {
      obs_td <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_q(Q2m, T2m, Ps) - 273.15, units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    if (!has_rh) {
      obs_rh_out <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_q(Q2m, T2m, Ps), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  list(Td2m = obs_td, RH2m = obs_rh_out, Q2m = obs_q_out)
}

# Verify moisture parameter
verify_moisture_param <- function(fcst_moisture, obs_data, param, param_desc, calc_func, units, offset, output_dir) {
  if (is.null(obs_data) || nrow(obs_data) == 0) return(FALSE)
  
  cat("  - Verifying", param_desc, "\n")
  
  fcst_list <- lapply(fcst_moisture, function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    if (!is.null(calc_func)) {
      df$fcst <- calc_func(as.numeric(df$q2m_val), as.numeric(df$t2m_val), as.numeric(df$psfc_val)) + offset
    } else {
      df$fcst <- df$q2m_val
    }
    
    df$parameter <- param
    df$units <- units
    df |> select(SID, valid_dttm, lead_time, fcst_dttm, parameter, fcst, units)
  })
  names(fcst_list) <- names(fcst_moisture)
  
  if (!is.null(obs_data) && "units" %in% names(obs_data)) {
    if (units == "percent" && any(obs_data$units == "%")) obs_data$units <- "percent"
  }
  
  fcst_list <- as_harp_list(fcst_list) |> set_units(units) |> common_cases() |> join_to_fcst(obs_data)

  for (model_name in names(fcst_list)) {
    model_data <- fcst_list[[model_name]]
    if (is.data.frame(model_data) && nrow(model_data) > 0) {
      if (param %in% names(model_data)) {
        model_data <- model_data |> filter(!is.na(fcst) & !is.na(.data[[param]]))
      } else {
        model_data <- model_data |> filter(!is.na(fcst))
      }
      fcst_list[[model_name]] <- model_data
    }
  }
  
  if (!any(sapply(fcst_list, function(x) is.data.frame(x) && nrow(x) > 0))) return(FALSE)

  verif <- tryCatch(det_verify(fcst_list, !!sym(param)), error = function(e) NULL)
  if (is.null(verif)) return(FALSE)

  save_point_verif(verif, verif_path = file.path(output_dir))
  cat("    - Saved\n")
  return(TRUE)
}

# Main script
opt <- parse_and_validate_args()

all_models <- c(opt$hourly_models, opt$multihourly_models)
cat("Starting verification:", opt$start_date, "to", opt$end_date, "\n")
cat("Output directory:", opt$output_dir, "\n")
cat("Models:", paste(all_models, collapse = ", "), "\n")
cat("  - Hourly:", if (length(opt$hourly_models) > 0) paste(opt$hourly_models, collapse = ", ") else "none", "\n")
cat("  - 3-hourly (interpolated):", if (length(opt$multihourly_models) > 0) paste(opt$multihourly_models, collapse = ", ") else "none", "\n")
cat("Parameters: T2m, Pressure, Moisture (Td/RH/Q), Wind Speed, Precipitation (1h/12h/24h)\n")

fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

fcst <- read_forecasts(opt$start_date, opt$end_date, opt$hourly_models, opt$multihourly_models, fcst_dir)
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
verify_and_save(fcst, obs, opt$output_dir, opt$start_date, opt$end_date)