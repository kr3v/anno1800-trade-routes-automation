# Trade Routes Analyzer Webapp - Development Log

## Overview

Browser-based visualization tool for Anno 1800 trade route automation mod logs. No backend - all processing client-side using File System Access API.

**Stack:** Vite + TypeScript + Chart.js (swappable)

## Directory Structure

```
webapp/
├── index.html              # Main HTML, tab structure, filter controls
├── package.json            # Dependencies: vite, typescript, chart.js
├── tsconfig.json           # Strict TypeScript config
├── vite.config.ts          # Build config with @ alias
├── .gitignore
└── src/
    ├── main.ts             # Entry point, wires up widgets to DOM
    ├── styles.css          # Dark theme CSS
    │
    ├── file-access/        # File System Access API wrapper
    │   ├── index.ts        # pickDirectory(), readFileAsJson(), etc.
    │   └── types.ts        # FileSystemDirectoryHandle types
    │
    ├── parsers/            # Data format parsers
    │   ├── index.ts        # Re-exports all parsers
    │   ├── texts.ts        # texts.json (good ID → name mapping)
    │   ├── trades.ts       # trade-executor-history.json
    │   ├── deficit-surplus.ts  # remaining-deficit/surplus.json
    │   ├── ship-logs.ts    # trade-execute-iteration.*.log
    │   ├── coordinates.ts  # Area scan TSV format (x,y,type,dir)
    │   └── area-files.ts   # Scans for TrRAt_*_area_scan_*.tsv files
    │
    ├── visualizations/     # Abstracted rendering layer (swappable)
    │   ├── types.ts        # ILineChart, IDataTable interfaces
    │   ├── index.ts        # Factory: createLineChart(), createDataTable()
    │   ├── charts/
    │   │   └── chartjs/
    │   │       ├── line-chart.ts   # Chart.js ILineChart impl
    │   │       └── index.ts
    │   ├── table/
    │   │   └── html-table.ts       # HTML table with heatmap colors
    │   └── canvas/
    │       ├── types.ts            # ICoordinateCanvas interface
    │       ├── pan-zoom-canvas.ts  # Interactive canvas (pan/zoom/legend)
    │       └── index.ts
    │
    ├── widgets/            # High-level UI components
    │   ├── index.ts        # Re-exports all widgets
    │   ├── trade-table.ts  # Trade history table
    │   ├── deficit-surplus.ts  # Deficit/surplus lists
    │   ├── ship-usage-chart.ts # Ship availability line chart
    │   └── area-visualizer.ts  # Coordinate canvas with filters
    │
    └── tabs/               # (planned) Tab abstractions
```

## Key Design Decisions

### Visualization Abstraction
Charts are behind interfaces (`ILineChart`, `ICoordinateCanvas`) so Chart.js can be swapped for ECharts/etc. Change implementation in `visualizations/index.ts` factory functions.

### Coordinate System
Area visualizer uses **inverted Y axis** (Y increases upward) to match game coordinates. Conversion helpers: `toScreenX/Y()`, `toDataX/Y()`.

### File Discovery
Area visualizer auto-discovers `TrRAt_{GameName}_area_scan_{CityName}.tsv` files and populates cascading dropdowns (Game → Region → City).

## Tabs

1. **Trades** - Trade history table + deficit/surplus display
   - Filters: time duration, region (OW/NW)
   - Files: `trade-executor-history.json`, `remaining-deficit.json`, `remaining-surplus.json`

2. **Ship Usage** - Line chart with ships available & tasks spawned
   - Shows raw data + moving average trend lines
   - Files: `trade-execute-iteration.*.log`, `*.log.hub`

3. **Area Visualizer** - Interactive pan/zoom canvas
   - Filters: Game, Region, City (or "All")
   - Legend showing point types (S/W/w/L/Y/N)
   - City labels at centroids when viewing multiple cities
   - Files: `TrRAt_*_area_scan_*.tsv`

## Data Formats

### trade-executor-history.json
```json
[{ "good_id": 1010200, "good_amount": 50, "area_src_name": "c1", "area_dst_name": "n2", "_start": "...", "_end": "..." }]
```

### remaining-deficit.json / remaining-surplus.json
```json
{ "1010200": { "Total": 150, "Areas": [{ "AreaName": "c1", "Amount": 100 }] } }
```

### Area scan TSV (coordinates)
```
prefix<TAB>x,y,type,direction
```
Types: S=occupied, W=water, w=load/unload, L=land, N=not accessible

## Commands

```bash
npm run dev     # Development server
npm run build   # Production build → dist/
```

## Browser Support

Requires File System Access API: Chrome 86+, Edge 86+. Not supported in Firefox/Safari.