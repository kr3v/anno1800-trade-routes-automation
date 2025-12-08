/**
 * Visualization factory functions
 * Change implementations here to swap chart libraries
 */

import type { ILineChart, IDataTable, TableOptions } from './types';
import type { ICoordinateCanvas, CoordinateCanvasOptions } from './canvas/types';
import { ChartJSLineChart } from './charts/chartjs';
import { HtmlDataTable } from './table/html-table';
import { PanZoomCanvas } from './canvas/pan-zoom-canvas';

export * from './types';
export * from './canvas/types';

/**
 * Chart implementation type
 * Add new implementations here as they become available
 */
export type ChartImplementation = 'chartjs';

/**
 * Create a line chart instance
 * @param impl - Implementation to use (default: 'chartjs')
 */
export function createLineChart(impl: ChartImplementation = 'chartjs'): ILineChart {
  switch (impl) {
    case 'chartjs':
      return new ChartJSLineChart();
    default:
      throw new Error(`Unknown chart implementation: ${impl}`);
  }
}

/**
 * Create a data table instance
 */
export function createDataTable(options: TableOptions): IDataTable {
  return new HtmlDataTable(options);
}

/**
 * Create a coordinate canvas instance
 */
export function createCoordinateCanvas(options?: Partial<CoordinateCanvasOptions>): ICoordinateCanvas {
  const canvas = new PanZoomCanvas();
  if (options) canvas.configure(options);
  return canvas;
}
