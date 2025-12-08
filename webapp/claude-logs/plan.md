# Trade Routes Automation Webapp - Implementation Plan

## Overview

Reimplement Python analysis scripts as a browser-based webapp with:
- File System Access API for reading game logs
- No backend - all processing client-side
- Static deployment (GitHub Pages)
- Tab-based UI with configurable visualization widgets

## Architecture

### Directory Structure

```
webapp/
├── index.html
├── vite.config.ts
├── tsconfig.json
├── package.json
├── src/
│   ├── main.ts                    # Entry point, tab routing
│   ├── styles.css                 # Minimal styling
│   │
│   ├── file-access/
│   │   ├── index.ts               # File System Access API wrapper
│   │   └── types.ts               # FileHandle types
│   │
│   ├── parsers/
│   │   ├── index.ts               # Re-exports
│   │   ├── trades.ts              # trade-executor-history.json
│   │   ├── deficit-surplus.ts     # remaining-deficit/surplus.json
│   │   ├── ship-logs.ts           # trade-execute-iteration.*.log
│   │   ├── coordinates.ts         # area-visualizer text format
│   │   └── texts.ts               # texts.json (good ID -> name mapping)
│   │
│   ├── visualizations/
│   │   ├── types.ts               # Abstract interfaces (CRITICAL)
│   │   ├── index.ts               # Factory functions
│   │   │
│   │   ├── charts/
│   │   │   ├── interface.ts       # ILineChart, IBarChart, etc.
│   │   │   ├── chartjs/           # Chart.js implementation
│   │   │   │   ├── line-chart.ts
│   │   │   │   ├── bar-chart.ts
│   │   │   │   └── index.ts
│   │   │   └── [future]/          # ECharts, Observable, etc.
│   │   │
│   │   ├── table/
│   │   │   ├── interface.ts       # IDataTable
│   │   │   └── html-table.ts      # Native HTML implementation
│   │   │
│   │   └── canvas/
│   │       ├── interface.ts       # ICoordinateCanvas
│   │       └── pan-zoom-canvas.ts # Interactive canvas impl
│   │
│   ├── widgets/
│   │   ├── trade-table.ts         # Combines parser + table viz
│   │   ├── deficit-surplus.ts     # Deficit/surplus display
│   │   ├── ship-usage-chart.ts    # Combines parser + line chart
│   │   └── area-visualizer.ts     # Combines parser + canvas
│   │
│   └── tabs/
│       ├── base-tab.ts            # Abstract tab class
│       ├── trades-tab.ts
│       ├── ship-usage-tab.ts
│       └── area-tab.ts
```

### Visualization Abstraction Layer

This is the key to making chart libraries swappable:

```typescript
// src/visualizations/types.ts

/** Data point for time series */
interface TimeSeriesPoint {
  timestamp: Date;
  value: number;
}

/** Series configuration */
interface SeriesConfig {
  id: string;
  label: string;
  color: string;
  data: TimeSeriesPoint[];
  lineStyle?: 'solid' | 'dashed';
  movingAverage?: number;  // window size, 0 = disabled
}

/** Abstract line chart interface */
interface ILineChart {
  /** Mount chart to a container element */
  mount(container: HTMLElement): void;

  /** Update chart with new series data */
  setSeries(series: SeriesConfig[]): void;

  /** Update configuration */
  configure(options: LineChartOptions): void;

  /** Clean up resources */
  destroy(): void;
}

interface LineChartOptions {
  title?: string;
  xAxisLabel?: string;
  yAxisLabel?: string;
  yAxisBothSides?: boolean;
  timeFormat?: string;
  showGrid?: boolean;
  showLegend?: boolean;
}
```

```typescript
// src/visualizations/index.ts

import { ChartJSLineChart } from './charts/chartjs/line-chart';
// Future: import { EChartsLineChart } from './charts/echarts/line-chart';

// Factory function - single place to swap implementations
export function createLineChart(): ILineChart {
  return new ChartJSLineChart();
  // Future: return new EChartsLineChart();
}
```

### Data Flow

```
[File System] → [Parser] → [Typed Data] → [Widget] → [Visualization]
                                              ↑
                                        [Configuration]
```

Example for ship usage:

```typescript
// 1. User selects folder via File System Access API
const dirHandle = await window.showDirectoryPicker();

// 2. Parser reads and parses log files
const logData = await parseShipLogs(dirHandle);
// Returns: { regular: TimeSeriesData[], hub: TimeSeriesData[] }

// 3. Widget configures visualization
const chart = createLineChart();
chart.mount(container);
chart.configure({
  title: 'Ship Availability & Task Spawning',
  yAxisBothSides: true,
  showGrid: true
});

// 4. Widget transforms data to series format
chart.setSeries([
  { id: 'regular-ships', label: 'Ships (Regular)', data: logData.regular.ships, color: '#2E86AB' },
  { id: 'regular-tasks', label: 'Tasks (Regular)', data: logData.regular.tasks, color: '#A23B72', lineStyle: 'dashed' },
  // ... hub series
]);
```

## Implementation Steps

### Phase 1: Project Setup

1. Initialize Vite + TypeScript project
   ```bash
   cd webapp
   npm create vite@latest . -- --template vanilla-ts
   npm install
   ```

2. Add dependencies
   ```bash
   npm install chart.js
   npm install -D @types/node
   ```

3. Configure TypeScript for strict mode

### Phase 2: Core Infrastructure

4. **File Access Module** (`file-access/`)
   - Wrapper around File System Access API
   - Directory handle management
   - File reading utilities (text, JSON)
   - Error handling for permission denied, etc.

5. **Parsers** (`parsers/`)
   - `texts.ts`: Load good ID → name mapping
   - `trades.ts`: Parse trade-executor-history.json
     - Filter by time duration
     - Aggregate by city/good
   - `deficit-surplus.ts`: Parse remaining-*.json
   - `ship-logs.ts`: Parse log files with regex
     - Handle both .log and .log.hub files
   - `coordinates.ts`: Parse area-visualizer format

### Phase 3: Visualization Layer

6. **Visualization Interfaces** (`visualizations/types.ts`)
   - Define abstract interfaces for all chart types
   - Keep interfaces implementation-agnostic

7. **Chart.js Implementations** (`visualizations/charts/chartjs/`)
   - `line-chart.ts`: Time series with multiple series, moving averages
   - `bar-chart.ts`: For deficit/surplus if needed

8. **HTML Table** (`visualizations/table/`)
   - Native HTML table with:
     - Heatmap cell coloring
     - Sortable columns
     - Box-drawing borders (CSS)

9. **Interactive Canvas** (`visualizations/canvas/`)
   - Pan/zoom with mouse/touch
   - Point rendering with colors
   - Arrow rendering for directions
   - Grid overlay
   - Coordinate display on hover

### Phase 4: Widgets

10. **Trade Table Widget**
    - Combines trades parser + table visualization
    - Configuration: time filter, sort order, color thresholds

11. **Deficit/Surplus Widget**
    - Simple list display with color coding
    - Grouped by good, showing areas

12. **Ship Usage Widget**
    - Combines ship-logs parser + line chart
    - Configuration: moving average window, series visibility

13. **Area Visualizer Widget**
    - Combines coordinates parser + canvas
    - Configuration: point colors, grid density

### Phase 5: Tab UI

14. **Tab Infrastructure**
    - Simple tab switching (no router needed)
    - Each tab lazy-loads its content
    - Tab state persistence (localStorage)

15. **Individual Tabs**
    - Trades tab: folder picker + trade table + deficit/surplus
    - Ship Usage tab: folder picker + ship usage chart
    - Area tab: file picker + coordinate canvas

### Phase 6: Polish

16. **Styling**
    - Dark/light theme (prefers-color-scheme)
    - Responsive layout
    - Loading states

17. **Error Handling**
    - User-friendly error messages
    - File format validation
    - Browser compatibility checks (File System Access API)

18. **Build & Deploy**
    - Vite build configuration
    - GitHub Pages deployment workflow

## Data Formats Reference

### trade-executor-history.json
```json
[
  {
    "good_id": 1010200,
    "good_name": "Timber",
    "good_amount": 50,
    "area_src_name": "c1",
    "area_dst_name": "n2",
    "_start": "2024-01-15T10:30:00Z",
    "_end": "2024-01-15T10:32:00Z"
  }
]
```

### remaining-deficit.json / remaining-surplus.json
```json
{
  "1010200": {
    "Total": 150,
    "Areas": [
      { "AreaName": "c1", "Amount": 100 },
      { "AreaName": "n2", "Amount": 50 }
    ]
  }
}
```

### trade-execute-iteration.*.log
```
2024-01-15T10:30:00Z [INFO] Starting trade execution
Total available trade route automation ships: 5
Spawned 3 async tasks for trade route execution
```

### Area visualizer format (text)
```
prefix 100,200,S,L
prefix 150,250,W,R
prefix 200,300,L
```

## Configuration Examples

### Trade Table Configuration
```typescript
tradeTable.configure({
  // Time filtering
  duration: '2h',  // or '15m', '1d', null for all

  // Visual
  colorScale: {
    received: { low: '#e8f5e9', high: '#2e7d32' },
    sent: { low: '#ffebee', high: '#c62828' }
  },
  thresholds: {
    bold: 0.75,  // % of max for bold
    color: 0.25  // % of max for color
  },

  // Sorting
  citySortOrder: 'volume',  // or 'name'
  goodSortOrder: 'volume',

  // Columns
  showNetColumn: true
});
```

### Line Chart Configuration
```typescript
shipChart.configure({
  // Series
  series: [
    { field: 'ships_available', mode: 'regular', visible: true },
    { field: 'tasks_spawned', mode: 'regular', visible: true },
    { field: 'ships_available', mode: 'hub', visible: true },
    { field: 'tasks_spawned', mode: 'hub', visible: true }
  ],

  // Moving average
  movingAverageWindow: 10,
  showRawData: true,  // show faded raw + solid trend

  // Axes
  yAxisBothSides: true,
  timeFormat: 'HH:mm:ss'
});
```

### Coordinate Canvas Configuration
```typescript
areaCanvas.configure({
  // Colors per point type
  colors: {
    'S': '#f44336',
    'W': '#90caf9',
    'w': '#1976d2',
    'L': '#a5d6a7',
    'Y': '#ffeb3b',
    'N': '#000000'
  },

  // Grid
  minorGridInterval: 10,
  majorGridInterval: 100,

  // Interaction
  showCoordinatesOnHover: true,
  enablePanZoom: true
});
```

## Browser Compatibility

File System Access API is required. Supported in:
- Chrome 86+
- Edge 86+
- Opera 72+

**Not supported**: Firefox, Safari

Fallback: Show message directing users to use Chrome/Edge, or implement file input fallback for read-only access.

## Future Extensibility

### Adding a New Chart Library (e.g., ECharts)

1. Create `src/visualizations/charts/echarts/` directory
2. Implement `ILineChart` interface
3. Update factory in `src/visualizations/index.ts`:
   ```typescript
   export function createLineChart(impl: 'chartjs' | 'echarts' = 'chartjs'): ILineChart {
     switch (impl) {
       case 'echarts': return new EChartsLineChart();
       default: return new ChartJSLineChart();
     }
   }
   ```

### Adding New Analysis Tabs

1. Create parser in `parsers/`
2. Create widget in `widgets/`
3. Create tab in `tabs/`
4. Register tab in `main.ts`

### Dashboard Mode (Future)

The widget abstraction allows composing multiple widgets:
```typescript
interface Dashboard {
  layout: GridLayout;
  widgets: WidgetConfig[];
}
```
