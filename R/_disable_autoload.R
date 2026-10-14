# This app sources util_scripts/ explicitly from app.R. Shiny treats the
# repository as an R package because DESCRIPTION has Type: Package and would
# otherwise warn while looking for support files in R/. This sentinel is the
# supported way to disable that implicit autoload path.
