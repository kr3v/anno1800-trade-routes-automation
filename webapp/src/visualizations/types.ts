/**
 * Abstract visualization interfaces
 * These interfaces allow swapping chart implementations
 */

/** Time series data point */
export interface TimeSeriesPoint {
  timestamp: Date;
  value: number;
}

/** Series configuration for line charts */
export interface SeriesConfig {
  id: string;
  label: string;
  color: string;
  data: TimeSeriesPoint[];
  lineStyle?: 'solid' | 'dashed';
  showPoints?: boolean;
  pointSize?: number;
  lineWidth?: number;
  opacity?: number;
}

/** Line chart options */
export interface LineChartOptions {
  title?: string;
  xAxisLabel?: string;
  yAxisLabel?: string;
  yAxisBothSides?: boolean;
  timeFormat?: string;
  showGrid?: boolean;
  showLegend?: boolean;
  legendPosition?: 'top' | 'bottom' | 'left' | 'right';
  aspectRatio?: number;
  responsive?: boolean;
}

/** Abstract line chart interface */
export interface ILineChart {
  /** Mount chart to a container element */
  mount(container: HTMLElement): void;

  /** Update chart with new series data */
  setSeries(series: SeriesConfig[]): void;

  /** Update configuration */
  configure(options: LineChartOptions): void;

  /** Resize chart */
  resize(): void;

  /** Reset zoom to default view */
  resetZoom?(): void;

  /** Clean up resources */
  destroy(): void;
}

/** Table column definition */
export interface TableColumn {
  id: string;
  label: string;
  sortable?: boolean;
  align?: 'left' | 'center' | 'right';
  width?: string;
  formatter?: (value: unknown, row: unknown) => string | HTMLElement;
}

/** Table row data */
export interface TableRow {
  [key: string]: unknown;
}

/** Cell style configuration */
export interface CellStyle {
  color?: string;
  backgroundColor?: string;
  fontWeight?: 'normal' | 'bold';
}

/** Cell styler function */
export type CellStyler = (value: unknown, row: TableRow, column: TableColumn) => CellStyle | null;

/** Table options */
export interface TableOptions {
  columns: TableColumn[];
  sortColumn?: string;
  sortDirection?: 'asc' | 'desc';
  cellStyler?: CellStyler;
  emptyMessage?: string;
}

/** Abstract table interface */
export interface IDataTable {
  /** Mount table to a container element */
  mount(container: HTMLElement): void;

  /** Set table data */
  setData(rows: TableRow[]): void;

  /** Update configuration */
  configure(options: Partial<TableOptions>): void;

  /** Sort by column */
  sort(columnId: string, direction?: 'asc' | 'desc'): void;

  /** Clean up resources */
  destroy(): void;
}
