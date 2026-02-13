# WRF Portal - Landing Page

library(shiny)
library(bslib)

ui <- page_fluid(
  title = "WRF Tools",
  
  h2("WRF Tools", class = "text-center mt-4 mb-4"),
  
  layout_columns(
    col_widths = c(6, 6),
    
    card(
      card_body(
        h3("📊 harpVis", class = "text-center"),
        p("Verification and analysis of NWP forecasts", class = "text-center"),
        hr(),
        actionButton(
          "btn_harpvis",
          "Open harpVis",
          class = "btn-primary btn-lg w-100",
          onclick = "window.open('/harpvis/', '_blank')"
        )
      )
    ),
    
    card(
      card_body(
        h3("🌍 WRF Visualization", class = "text-center"),
        p("Interactive visualization of WRF model output", class = "text-center"),
        hr(),
        actionButton(
          "btn_wrfviz",
          "Open WRF Visualization",
          class = "btn-success btn-lg w-100",
          onclick = "window.open('/wrf-viz/', '_blank')"
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # No server logic needed - this is just a landing page
}

shinyApp(ui = ui, server = server)