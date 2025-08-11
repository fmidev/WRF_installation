library(shiny)
library(harpVis)

# Set options for file navigation
shinyOptions(
  app_start_dir = system.file("verification", package = "harpVis"),
  full_dir_navigation = TRUE
)

ui <- fluidPage(
  fluidRow(
    column(12,
      # File loading interface
      options_barUI("file_opts")
    )
  ),
  fluidRow(
    column(4,
      # Metrics selector UI
      selectInput(
        "metrics",
        "Select Metrics to Display:",
        choices = c("RMSE", "MAE", "Bias", "CRPS", "Spread"),
        selected = c("RMSE", "MAE"),
        multiple = TRUE
      )
    ),
    column(8,
      # Dashboard output for point verification
      dashboard_point_verifUI("pt_dshbrd")
    )
  )
)

server <- function(input, output, session) {
  # Reactive: loaded verification data
  verif_data <- callModule(options_bar, "file_opts")
  
  # Improved colour table with descriptive labels
  colour_table <- reactive({
    df <- verif_data()
    models <- unique(df$ens_summary_scores$fcst_model)
    # Assign distinct colours and labels
    data.frame(
      fcst_model = models,
      colour = rainbow(length(models)),
      label = paste("Model:", models)
    )
  })
  
  # Define time axis for the dashboard
  time_axis <- reactive("lead_time")
  
  # Call the point verification dashboard module with selected metrics
  callModule(
    dashboard_point_verif,
    "pt_dshbrd",
    reactive(verif_data()),
    reactive(colour_table()),
    time_axis,
    reactive(input$metrics) # Pass selected metrics to the module
  )
}

shinyApp(ui, server)
