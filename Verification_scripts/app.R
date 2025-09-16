library(shiny)
library(harpVis)
library(DT)
library(plotly)
library(dplyr)
library(ggplot2)

# Set options for file navigation
shinyOptions(
  app_start_dir = system.file("verification", package = "harpVis"),
  full_dir_navigation = TRUE
)

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      .content-wrapper {
        margin: 20px;
      }
      .error-box {
        background-color: #f8d7da;
        border: 1px solid #f5c6cb;
        color: #721c24;
        padding: 12px;
        border-radius: 4px;
        margin: 10px 0;
      }
      .success-box {
        background-color: #d4edda;
        border: 1px solid #c3e6cb;
        color: #155724;
        padding: 12px;
        border-radius: 4px;
        margin: 10px 0;
      }
      .info-box {
        background-color: #e3f2fd;
        border: 1px solid #bbdefb;
        color: #0d47a1;
        padding: 12px;
        border-radius: 4px;
        margin: 10px 0;
      }
      .main-title {
        background: linear-gradient(135deg, #1976d2 0%, #0d47a1 50%, #004085 100%);
        color: white;
        padding: 25px;
        margin: -15px -15px 20px -15px;
        border-radius: 0;
        box-shadow: 0 4px 6px rgba(0,0,0,0.1);
      }
      .model-badge {
        display: inline-block;
        background: rgba(255,255,255,0.2);
        padding: 5px 12px;
        border-radius: 15px;
        font-size: 0.8em;
        margin-left: 10px;
      }
      .metric-panel {
        background: linear-gradient(to bottom, #f8f9ff 0%, #ffffff 100%);
        border: 1px solid #e3f2fd;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.05);
      }
      .weather-icon {
        color: #1976d2;
        margin-right: 8px;
      }
    "))
  ),
  
  div(class = "main-title",
    div(style = "text-align: center;",
      h1("NWP Model Verification Dashboard", style = "margin: 0; font-weight: bold;"),
      div(class = "model-badge", "Multi-Model Forecast Verification"),
      br(),
      p("Advanced Numerical Weather Prediction Model Comparison & Analysis", 
        style = "margin: 10px 0 0 0; font-size: 1.1em; opacity: 0.9;")
    )
  ),
  
  div(class = "content-wrapper",
    # Status display
    uiOutput("status_display"),
    
    # File loading interface
    fluidRow(
      column(12,
        wellPanel(class = "metric-panel",
          h3("🌩️ Model Forecast Data Loading", style = "color: #1976d2; margin-top: 0;"),
          div(
            div(class = "info-box",
              h4("📋 Loading Model Verification Data:"),
              p("1. Click 'Browse' to navigate to your model verification files"),
              p("2. Look for .rds files containing forecast verification data (WRF, GFS, ECMWF, etc.)"),
              p("3. Select a file and click 'Load' to begin multi-model verification analysis"),
              p(strong("Supported models:"), "WRF (d01, d02), GFS, ECMWF, and other NWP models"),
              br(),
              actionButton("load_example", "Load Example Data", class = "btn-info", 
                          style = "margin-right: 10px; background-color: #1976d2; border-color: #1976d2;"),
              span("or use the file browser below to load your model output:")
            )
          ),
          br(),
          options_barUI("file_opts")
        )
      )
    ),
    
    # Data summary
    fluidRow(
      column(12,
        conditionalPanel(
          condition = "output.data_available",
          wellPanel(class = "metric-panel",
            h3("📊 Model Data Summary", style = "color: #1976d2; margin-top: 0;"),
            verbatimTextOutput("data_summary")
          )
        )
      )
    ),
    
    # Main dashboard
    fluidRow(
      column(12,
        conditionalPanel(
          condition = "output.data_available",
          wellPanel(class = "metric-panel",
            h3("📈 Model Verification Dashboard", style = "color: #1976d2; margin-top: 0;"),
            p("Core verification metrics for numerical weather prediction model performance", 
              style = "color: #666; margin-bottom: 15px;"),
            dashboard_point_verifUI("pt_dshbrd")
          )
        )
      )
    ),
    
    # Enhanced features section
    conditionalPanel(
      condition = "output.data_available",
      fluidRow(
        column(6,
          wellPanel(class = "metric-panel",
            h3("🌡️ Meteorological Verification Metrics", style = "color: #1976d2; margin-top: 0;"),
            p("Analyze meteorological variables across different forecast models", 
              style = "color: #666; margin-bottom: 15px;"),
            fluidRow(
              column(6,
                selectInput("metric_type", "Select Verification Metric:", 
                           choices = list(
                             "Temperature Metrics" = list(
                               "Bias (Temperature)" = "bias",
                               "RMSE (Root Mean Square Error)" = "rmse", 
                               "MAE (Mean Absolute Error)" = "mae",
                               "Standard Deviation" = "stde"
                             ),
                             "Statistical Metrics" = list(
                               "Correlation Coefficient" = "corr",
                               "Mean Error" = "me",
                               "Forecast Std Dev" = "fsd"
                             )
                           ),
                           selected = "bias")
              ),
              column(6,
                selectInput("plot_type", "Visualization Type:",
                           choices = list(
                             "Time Series" = "line",
                             "Interactive Plot" = "interactive",
                             "Distribution" = "box"
                           ),
                           selected = "line")
              )
            ),
            conditionalPanel(
              condition = "input.plot_type == 'interactive'",
              plotlyOutput("interactive_plot", height = "400px")
            ),
            conditionalPanel(
              condition = "input.plot_type != 'interactive'",
              plotOutput("additional_plot", height = "400px")
            )
          )
        ),
        column(6,
          wellPanel(class = "metric-panel",
            h3("🏆 Multi-Model Performance Ranking", style = "color: #1976d2; margin-top: 0;"),
            p("Compare WRF domains (d01, d02) with global models (GFS, ECMWF)", 
              style = "color: #666; margin-bottom: 15px;"),
            selectInput("ranking_metric", "Rank Models by:",
                       choices = list(
                         "RMSE (Lower = Better Accuracy)" = "rmse",
                         "Bias (Closer to 0 = Better)" = "bias",
                         "MAE (Lower = Better Precision)" = "mae",
                         "Correlation (Higher = Better Fit)" = "corr"
                       ),
                       selected = "rmse"),
            plotOutput("ranking_plot", height = "400px")
          )
        )
      ),
      
      # Statistics table
      fluidRow(
        column(12,
          wellPanel(class = "metric-panel",
            h3("📋 Model Verification Statistics", style = "color: #1976d2; margin-top: 0;"),
            p("Detailed statistical analysis of forecast model performance with export capabilities", 
              style = "color: #666; margin-bottom: 15px;"),
            DTOutput("enhanced_score_table")
          )
        )
      )
    ),
    
    # Help section
    fluidRow(
      column(12,
        wellPanel(class = "metric-panel",
          h3("❓ Multi-Model Verification Guide", style = "color: #1976d2; margin-top: 0;"),
          div(
            h4("🌩️ How to use this Multi-Model Verification Dashboard:"),
            tags$ol(
              tags$li("Load your forecast verification data using the 'Model Forecast Data Loading' section"),
              tags$li("Review the 'Model Data Summary' to understand your loaded dataset"),
              tags$li("Analyze core model performance with the main verification dashboard (bias and RMSE)"),
              tags$li("Explore meteorological-specific metrics in the 'Meteorological Verification Metrics' panel"),
              tags$li("Compare different models using the multi-model performance ranking"),
              tags$li("Export detailed statistics for further analysis or reporting")
            ),
            br(),
            h4("🌡️ Verification Metrics Explained:"),
            div(style = "background-color: #f8f9ff; padding: 15px; border-radius: 5px; border-left: 4px solid #1976d2;",
              tags$ul(
                tags$li(strong("Bias:"), " Mean difference between model forecast and observations. Indicates systematic over/under-prediction."),
                tags$li(strong("RMSE:"), " Root Mean Square Error - Overall accuracy of model forecasts. Lower values indicate better performance."),
                tags$li(strong("MAE:"), " Mean Absolute Error - Average magnitude of forecast errors without considering direction."),
                tags$li(strong("Correlation:"), " Linear relationship strength between model forecasts and observations (0-1, higher is better)."),
                tags$li(strong("Standard Deviation:"), " Measure of forecast variability and consistency across models.")
              )
            ),
            br(),
            h4("🔬 Supported Model Types:"),
            div(style = "background-color: #e3f2fd; padding: 15px; border-radius: 5px;",
              p("This dashboard supports verification and comparison of:"),
              tags$ul(
                tags$li(strong("WRF Models:"), " High-resolution nested domains (d01, d02) with different physics configurations"),
                tags$li(strong("Global Models:"), " GFS, ECMWF, UKMO, and other operational forecast centers"),
                tags$li(strong("Ensemble Systems:"), " Multi-member ensemble forecasts and probabilistic verification"),
                tags$li(strong("Regional Models:"), " NAM, HRRR, and other high-resolution regional models"),
                tags$li(strong("Research Models:"), " Experimental configurations and sensitivity studies")
              ),
              br(),
              p(strong("Model Comparison Features:")),
              tags$ul(
                tags$li("Lead time analysis and forecast degradation assessment"),
                tags$li("Cross-model performance evaluation and ranking"),
                tags$li("Variable-specific verification (temperature, wind, pressure, precipitation)"),
                tags$li("Seasonal and regional model performance evaluation")
              )
            )
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Status tracking
  status <- reactiveValues(
    error = NULL,
    message = NULL,
    data_loaded = FALSE
  )
  
  # Server initialization debugging
  cat("=== NWP MODEL VERIFICATION SERVER STARTED ===\n")
  cat("Shiny version:", as.character(packageVersion("shiny")), "\n")
  cat("harpVis available:", "harpVis" %in% rownames(installed.packages()), "\n")
  showNotification("Multi-Model Verification Dashboard started - ready for model analysis", type = "message", duration = 3)
  
  # Status display
  output$status_display <- renderUI({
    if (!is.null(status$error)) {
      div(class = "error-box", "⚠️ ", status$error)
    } else if (!is.null(status$message)) {
      div(class = "success-box", "✅ ", status$message)
    } else if (!status$data_loaded) {
      div(class = "info-box", "🌩️ Please load model verification data using the options above to begin model analysis.")
    }
  })
  
  # Use moduleServer for newer Shiny versions, fallback to callModule for older versions
  verif_data <- tryCatch({
    cat("=== INITIALIZING DATA MODULE ===\n")
    cat("moduleServer exists:", exists("moduleServer"), "\n")
    
    if (exists("moduleServer")) {
      cat("Using moduleServer for options_bar\n")
      result <- moduleServer("file_opts", options_bar)
      cat("moduleServer result type:", class(result), "\n")
      result
    } else {
      cat("Using callModule for options_bar\n")
      result <- callModule(options_bar, "file_opts") 
      cat("callModule result type:", class(result), "\n")
      result
    }
  }, error = function(e) {
    status$error <<- paste("Error loading data module:", e$message)
    showNotification(paste("Data module error:", e$message), type = "error", duration = 10)
    reactive(NULL)
  })
  
  # Add debugging for data loading
  observeEvent(verif_data(), {
    cat("=== DATA LOADING EVENT ===\n")
    data <- verif_data()
    if (is.null(data)) {
      cat("No data received\n")
      status$error <<- "No data was loaded. Please check your file selection and try again."
    } else {
      cat("Data received! Type:", class(data), "\n")
      cat("Data structure:\n")
      print(str(data))
      
      if (is.list(data)) {
        cat("List elements:", paste(names(data), collapse = ", "), "\n")
      }
      
      showNotification("Data loading attempted - check console for details", type = "message", duration = 5)
    }
  })
  
  # Load example data
  example_data <- reactiveVal()
  
  # Manual load example data
  observeEvent(input$load_example, {
    showNotification("Loading example model verification data...", type = "message", duration = 3)
    
    tryCatch({
      # Get the verification directory
      verif_dir <- system.file("verification", package = "harpVis")
      
      # Find a suitable example file
      example_files <- list.files(verif_dir, pattern = "\\.rds$", full.names = TRUE, recursive = TRUE)
      
      if (length(example_files) > 0) {
        # Use the first available example file
        example_file <- example_files[1]
        cat("Loading model example file:", example_file, "\n")
        
        # Load the data
        data <- readRDS(example_file)
        example_data(data)
        
        status$data_loaded <<- TRUE
        status$message <<- paste("Model example data loaded from:", basename(example_file))
        status$error <<- NULL
        
        showNotification(paste("Successfully loaded model verification data from:", basename(example_file)), 
                        type = "message", duration = 8)
      } else {
        status$error <<- "No example model verification files found in package"
        showNotification("No example model data files found", type = "error", duration = 5)
      }
      
    }, error = function(e) {
      status$error <<- paste("Error loading model example data:", e$message)
      showNotification(paste("Error loading model example data:", e$message), type = "error", duration = 8)
    })
  })
  
  # Combine regular data loading with example data
  combined_data <- reactive({
    regular_data <- verif_data()
    example <- example_data()
    
    # Prioritize regular loaded data over example data
    if (!is.null(regular_data)) {
      return(regular_data)
    } else if (!is.null(example)) {
      return(example)
    } else {
      return(NULL)
    }
  })
  
  colour_table <- reactive({
    tryCatch({
      df <- combined_data()
      cat("=== COLOUR TABLE UPDATE ===\n")
      cat("Data received in colour_table:", !is.null(df), "\n")
      
      if (is.null(df)) {
        status$message <<- "Waiting for data to be loaded..."
        status$data_loaded <<- FALSE
        return(data.frame(fcst_model = character(), colour = character()))
      }
      
      cat("Data type:", class(df), "\n")
      if (is.list(df)) {
        cat("List names:", paste(names(df), collapse = ", "), "\n")
      }
      
      status$data_loaded <<- TRUE
      status$message <<- "Data loaded successfully!"
      status$error <<- NULL
      
      # Handle different data structures
      models <- character(0)
      
      if (!is.null(df$ens_summary_scores)) {
        cat("Found ens_summary_scores\n")
        models <- unique(na.omit(df$ens_summary_scores$fcst_model))
        cat("Models from ens_summary_scores:", paste(models, collapse = ", "), "\n")
      } else if (!is.null(df$det_summary_scores)) {
        cat("Found det_summary_scores\n")
        models <- unique(na.omit(df$det_summary_scores$fcst_model))
        cat("Models from det_summary_scores:", paste(models, collapse = ", "), "\n")
      } else if (is.list(df) && length(df) > 0) {
        cat("Using list names as models\n")
        # Try to extract model names from list structure
        models <- names(df)
        cat("Models from list names:", paste(models, collapse = ", "), "\n")
      } else {
        cat("No recognizable data structure found\n")
        cat("Available elements in data:\n")
        if (is.list(df)) {
          for (name in names(df)) {
            cat("  -", name, ":", class(df[[name]]), "\n")
          }
        }
        status$error <<- "Data loaded but structure not recognized. Expected 'det_summary_scores' or 'ens_summary_scores'."
      }
      
      if (length(models) > 0) {
        cat("Creating colour table for", length(models), "models\n")
        result <- data.frame(
          fcst_model = models,
          colour = rainbow(length(models)),
          stringsAsFactors = FALSE
        )
        showNotification(paste("Successfully loaded data for", length(models), "model(s):", paste(models, collapse = ", ")), 
                        type = "message", duration = 8)
        return(result)
      } else {
        status$error <<- "No forecast models found in the loaded data."
        return(data.frame(fcst_model = character(), colour = character()))
      }
      
    }, error = function(e) {
      cat("Error in colour_table:", e$message, "\n")
      status$error <<- paste("Error processing data:", e$message)
      showNotification(paste("Error processing data:", e$message), type = "error", duration = 10)
      return(data.frame(fcst_model = character(), colour = character()))
    })
  })
  
  # Data availability flag
  output$data_available <- reactive({
    data <- combined_data()
    !is.null(data) && status$data_loaded
  })
  outputOptions(output, "data_available", suspendWhenHidden = FALSE)
  
  # Data summary
  output$data_summary <- renderText({
    df <- combined_data()
    if (is.null(df)) return("No data loaded")
    
    summary_text <- "Data Structure:\n"
    if (is.list(df)) {
      summary_text <- paste0(summary_text, "- Type: List with ", length(df), " elements\n")
      summary_text <- paste0(summary_text, "- Elements: ", paste(names(df), collapse = ", "), "\n")
      
      if (!is.null(df$det_summary_scores)) {
        summary_text <- paste0(summary_text, "- Deterministic scores: ", nrow(df$det_summary_scores), " rows\n")
        if ("lead_time" %in% names(df$det_summary_scores)) {
          lead_times <- range(df$det_summary_scores$lead_time, na.rm = TRUE)
          summary_text <- paste0(summary_text, "- Lead times: ", lead_times[1], " to ", lead_times[2], " hours\n")
        }
        # Show available parameters
        score_cols <- intersect(names(df$det_summary_scores), 
                               c("bias", "rmse", "mae", "corr", "stde", "me", "fsd"))
        if (length(score_cols) > 0) {
          summary_text <- paste0(summary_text, "- Available metrics: ", paste(score_cols, collapse = ", "), "\n")
        }
      }
      if (!is.null(df$ens_summary_scores)) {
        summary_text <- paste0(summary_text, "- Ensemble scores: ", nrow(df$ens_summary_scores), " rows\n")
      }
    }
    
    summary_text
  })
  
  # Define time axis for the dashboard
  time_axis <- reactive("lead_time")
  
  # Call the point verification dashboard module with error handling
  observe({
    tryCatch({
      data <- combined_data()
      if (!is.null(data) && status$data_loaded) {
        if (exists("moduleServer")) {
          moduleServer("pt_dshbrd", function(input, output, session) {
            dashboard_point_verif(input, output, session, 
                                reactive(combined_data()), 
                                reactive(colour_table()), 
                                time_axis)
          })
        } else {
          callModule(
            dashboard_point_verif,
            "pt_dshbrd",
            reactive(combined_data()),
            reactive(colour_table()),
            time_axis
          )
        }
      }
    }, error = function(e) {
      status$error <<- paste("Dashboard error:", e$message)
    })
  })
  
  # Additional plot
  output$additional_plot <- renderPlot({
    req(input$metric_type)
    
    tryCatch({
      df <- combined_data()
      if (is.null(df)) return(NULL)
      
      # Try both deterministic and ensemble scores
      plot_data <- NULL
      if (!is.null(df$det_summary_scores)) {
        plot_data <- df$det_summary_scores
      } else if (!is.null(df$ens_summary_scores)) {
        plot_data <- df$ens_summary_scores
      }
      
      if (is.null(plot_data) || !input$metric_type %in% names(plot_data)) {
        return(ggplot() + 
               annotate("text", x = 1, y = 1, label = "No data available for selected metric", 
                       size = 4) +
               theme_void())
      }
      
      if (input$plot_type == "line") {
        p <- ggplot(plot_data, aes_string(x = "lead_time", y = input$metric_type)) +
          geom_line(aes(color = fcst_model), size = 1.2) +
          geom_point(aes(color = fcst_model), size = 2.5) +
          theme_minimal() +
          labs(
            title = paste("Model", toupper(input$metric_type), "- Lead Time Analysis"),
            x = "Forecast Lead Time (hours)",
            y = paste("Model", toupper(input$metric_type)),
            color = "Forecast Model"
          ) +
          theme(
            legend.position = "bottom",
            plot.title = element_text(size = 14, face = "bold", color = "#1976d2"),
            axis.text = element_text(size = 11),
            axis.title = element_text(size = 12)
          )
      } else if (input$plot_type == "box") {
        p <- ggplot(plot_data, aes_string(x = "fcst_model", y = input$metric_type)) +
          geom_boxplot(aes(fill = fcst_model), alpha = 0.7) +
          geom_jitter(width = 0.2, alpha = 0.5) +
          theme_minimal() +
          labs(
            title = paste("Model", toupper(input$metric_type), "Distribution by Model"),
            x = "Model Configuration",
            y = paste("Model", toupper(input$metric_type))
          ) +
          theme(
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "none",
            plot.title = element_text(size = 14, face = "bold", color = "#1976d2")
          )
      }
      
      return(p)
        
    }, error = function(e) {
      ggplot() + 
        annotate("text", x = 1, y = 1, 
                label = paste("Error creating plot:", e$message), 
                size = 3, color = "red") +
        theme_void()
    })
  })
  
  # Interactive plot
  output$interactive_plot <- renderPlotly({
    req(input$metric_type)
    
    tryCatch({
      df <- combined_data()
      if (is.null(df)) return(NULL)
      
      plot_data <- NULL
      if (!is.null(df$det_summary_scores)) {
        plot_data <- df$det_summary_scores
      } else if (!is.null(df$ens_summary_scores)) {
        plot_data <- df$ens_summary_scores
      }
      
      if (is.null(plot_data) || !input$metric_type %in% names(plot_data)) {
        return(plotly_empty() %>%
               add_annotations(text = "No data available", 
                              xref = "paper", yref = "paper",
                              x = 0.5, y = 0.5, showarrow = FALSE))
      }
      
      p <- ggplot(plot_data, aes_string(x = "lead_time", y = input$metric_type)) +
        geom_line(aes(color = fcst_model), size = 1.2) +
        geom_point(aes(color = fcst_model), size = 2.5) +
        theme_minimal() +
        labs(
          title = paste("Interactive Model", toupper(input$metric_type), "Analysis"),
          x = "Forecast Lead Time (hours)",
          y = paste("Model", toupper(input$metric_type)),
          color = "Forecast Model"
        ) +
        theme(legend.position = "bottom")
      
      ggplotly(p, tooltip = c("x", "y", "colour"))
      
    }, error = function(e) {
      plotly_empty() %>%
        add_annotations(text = paste("Error:", e$message), 
                       xref = "paper", yref = "paper",
                       x = 0.5, y = 0.5, showarrow = FALSE)
    })
  })
  
  # Ranking plot
  output$ranking_plot <- renderPlot({
    req(input$ranking_metric)
    
    tryCatch({
      df <- combined_data()
      if (is.null(df)) return(NULL)
      
      plot_data <- NULL
      if (!is.null(df$det_summary_scores)) {
        plot_data <- df$det_summary_scores
      } else if (!is.null(df$ens_summary_scores)) {
        plot_data <- df$ens_summary_scores
      }
      
      if (is.null(plot_data) || !input$ranking_metric %in% names(plot_data)) {
        return(ggplot() + 
               annotate("text", x = 1, y = 1, label = "No data available for ranking", 
                       size = 4) +
               theme_void())
      }
      
      # Calculate summary statistics
      if (input$ranking_metric == "bias") {
        # For bias, we want values closer to 0
        summary_data <- plot_data %>%
          group_by(fcst_model) %>%
          summarise(
            mean_value = abs(mean(.data[[input$ranking_metric]], na.rm = TRUE)),
            .groups = "drop"
          )
        title_text <- "Model Ranking by Absolute Bias (lower = better performance)"
      } else if (input$ranking_metric == "corr") {
        # For correlation, higher is better
        summary_data <- plot_data %>%
          group_by(fcst_model) %>%
          summarise(
            mean_value = mean(.data[[input$ranking_metric]], na.rm = TRUE),
            .groups = "drop"
          ) %>%
          arrange(desc(mean_value))  # Sort descending for correlation
        title_text <- "Model Ranking by Correlation (higher = better performance)"
      } else {
        # For RMSE, MAE etc., lower is better
        summary_data <- plot_data %>%
          group_by(fcst_model) %>%
          summarise(
            mean_value = mean(.data[[input$ranking_metric]], na.rm = TRUE),
            .groups = "drop"
          )
        title_text <- paste("Model Ranking by", toupper(input$ranking_metric), "(lower = better performance)")
      }
      
      # Create ranking plot
      if (input$ranking_metric == "corr") {
        p <- ggplot(summary_data, aes(x = reorder(fcst_model, mean_value), y = mean_value)) +
          geom_col(aes(fill = fcst_model), alpha = 0.8) +
          coord_flip() +
          theme_minimal() +
          labs(
            title = title_text,
            x = "Model Configuration",
            y = paste("Mean", toupper(input$ranking_metric))
          ) +
          theme(legend.position = "none", 
                plot.title = element_text(size = 12, face = "bold", color = "#1976d2"))
      } else {
        p <- ggplot(summary_data, aes(x = reorder(fcst_model, -mean_value), y = mean_value)) +
          geom_col(aes(fill = fcst_model), alpha = 0.8) +
          coord_flip() +
          theme_minimal() +
          labs(
            title = title_text,
            x = "Model Configuration",
            y = paste("Mean", toupper(input$ranking_metric))
          ) +
          theme(legend.position = "none", 
                plot.title = element_text(size = 12, face = "bold", color = "#1976d2"))
      }
      
      return(p)
      
    }, error = function(e) {
      ggplot() + 
        annotate("text", x = 1, y = 1, 
                label = paste("Error creating ranking:", e$message), 
                size = 3, color = "red") +
        theme_void()
    })
  })
  
  # Enhanced statistics table
  output$enhanced_score_table <- renderDT({
    tryCatch({
      df <- combined_data()
      if (is.null(df)) return(NULL)
      
      score_data <- NULL
      if (!is.null(df$det_summary_scores)) {
        score_data <- df$det_summary_scores
      } else if (!is.null(df$ens_summary_scores)) {
        score_data <- df$ens_summary_scores
      }
      
      if (is.null(score_data)) {
        return(datatable(data.frame(Message = "No score data available"), 
                        options = list(dom = 't'), rownames = FALSE))
      }
      
      # Select relevant columns for display
      display_cols <- intersect(names(score_data), 
                              c("fcst_model", "lead_time", "bias", "rmse", "mae", "corr", "stde", "me", "fsd"))
      
      if (length(display_cols) > 0) {
        datatable(
          score_data[, display_cols, drop = FALSE],
          options = list(
            pageLength = 15,
            scrollX = TRUE,
            dom = 'Bfrtip',
            buttons = list(
              'copy',
              list(extend = 'csv', filename = paste0('model_verification_', Sys.Date())),
              list(extend = 'excel', filename = paste0('model_verification_', Sys.Date()))
            ),
            columnDefs = list(
              list(className = 'dt-center', targets = '_all')
            )
          ),
          extensions = 'Buttons',
          rownames = FALSE,
          caption = "Model verification statistics. Export data using the buttons above for further analysis."
        ) %>%
        formatRound(columns = intersect(c("bias", "rmse", "mae", "corr", "stde", "me", "fsd"), display_cols), 
                   digits = 4)
      } else {
        datatable(data.frame(Message = "No displayable score data found"), 
                 options = list(dom = 't'), rownames = FALSE)
      }
      
    }, error = function(e) {
      datatable(data.frame(Error = paste("Error loading table:", e$message)), 
               options = list(dom = 't'), rownames = FALSE)
    })
  })
}

shinyApp(ui, server)