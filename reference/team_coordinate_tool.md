# Create the TeamCoordinate tool

Exposes `team_coordinate()` so the model can run a work-stealing team
over a shared board (uneven task sizes auto-balanced), distinct from
TeamRun's fixed fan-out.

## Usage

``` r
team_coordinate_tool(model = NULL, cwd = getwd())
```

## Arguments

  - model:
    
    Character. Default model for team agents.

  - cwd:
    
    Character. Working directory.

## Value

An `ellmer::tool()` object.
