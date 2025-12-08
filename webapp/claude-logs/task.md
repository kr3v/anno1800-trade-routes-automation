trade-routes-automation is an Anno 1800 "mod (that) manages a set of ships to transfer goods between islands inside a region, based on islands' goods stock and
requests".

`/data/games/steam/steamapps/compatdata/916440/pfx/drive_c/users/steamuser/Documents/Anno 1800/log/`

The mod exposes its state and some logs in ^^^ alike path.

I had custom Python scripts that analyzed the logs and state:
- [analyze_trades.py](../utils/analyze_trades.py)
- [area-visualizer.py](../utils/area-visualizer.py)
- [plot_ship_usage.py](../utils/plot_ship_usage.py)


Claude summary about those scripts:
```
  utils/analyze_trades.py

  Trade route analysis and goods flow visualization
  
  Features:
  - Trade history table - Shows received (↑) and sent (↓) goods per city in a formatted table with box-drawing characters
  - Color-coded amounts - Uses red/green colors with intensity based on trade volume (bold for high volumes)
  - Deficit/surplus analysis - Displays which goods are needed/oversupplied in each area
  - Time filtering - --duration flag to show trades from last X minutes/hours/days (e.g., --duration 15m, 2h, 1d)
  - Smart sorting - Cities grouped by type (c*/n*) and sorted by trade volume, goods sorted by total volume
  - Good name resolution - Translates numeric good IDs to readable names using texts.json

  utils/area-visualizer.py

  Coordinate visualization tool for game areas

  Features:
  - Bounding box visualization - Draws rectangle around all parsed coordinates
  - Colored point types - Supports color coding: S=red, W=lightblue, w=blue, L=lightgreen, Y=yellow, N=black
  - Directional arrows - Shows arrival direction with arrows (L=left, R=right, U=up, D=down)
  - Grid overlay - Minor grid every 10 pixels, major ticks at 50/100 pixel intervals
  - Auto-scaling - Automatically adjusts axis ranges and grid density based on coordinate range
  - High-res export - Saves 300 DPI PNG images

  utils/plot_ship_usage.py

  Ship utilization and task spawning tracker

  Features:
  - Dual mode tracking - Monitors both regular and hub trade routes separately
  - 4-line visualization - Shows ships available and tasks spawned for each mode
  - Moving average trends - Calculates and plots smoothed trend lines (default 10-point window)
  - Time-series plot - X-axis formatted with timestamps, shows data over time
  - Summary statistics - Prints average ship availability and task spawning rates
  - Log file parsing - Automatically discovers and parses trade-execute-iteration.*.log files
  - High-resolution output - 200 DPI, 24x8 inch wide plots for detailed analysis
```

I wish to reimplement those scripts as a webapp that can be used in-browser.

The webapp:
- should access the log folder via file system API
- should NOT have any backend, all processing should be done in-browser,
- be deployed as a static website (e.g., GitHub pages)

I'd prefer the webapp was understandable for my backend developer mind.
I prefer statically typed languages.``
I have 'product' data analysis experience (Datadog, Grafana; Redash, Metabase, ClickHouse), but not really pandas/NumPy or frontend development.

The webapp should be simple, yet extensible to add more analysis in the future.
I have no experience in frontend web development, so please suggest suitable frameworks/libraries.
The main goal is data visualization, so please suggest suitable charting/visualization libraries.

My vision is that the app should simply have multiple tabs, tab implementing each visualization feature.
Maybe tabs should be composable into a dashboard in the future?

Please provide a detailed plan for implementing this webapp. Please ask any clarifying questions if needed.
