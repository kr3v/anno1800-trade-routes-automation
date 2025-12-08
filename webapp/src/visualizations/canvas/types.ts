/**
 * Canvas visualization types
 */

import type { CoordinatePoint } from '@/parsers/coordinates';

/** Canvas options */
export interface CoordinateCanvasOptions {
  /** Colors per point type */
  colors?: Record<string, string>;
  /** Minor grid interval (pixels in data space) */
  minorGridInterval?: number;
  /** Major grid interval (pixels in data space) */
  majorGridInterval?: number;
  /** Show coordinates on hover */
  showCoordinatesOnHover?: boolean;
  /** Enable pan and zoom */
  enablePanZoom?: boolean;
  /** Point radius */
  pointRadius?: number;
  /** Arrow size */
  arrowSize?: number;
  /** Padding around bounds */
  padding?: number;
}

/** Coordinate canvas interface */
export interface ICoordinateCanvas {
  /** Mount canvas to a container */
  mount(container: HTMLElement): Promise<void>;

  /** Set points to render */
  setPoints(points: CoordinatePoint[]): void;

  /** Update configuration */
  configure(options: Partial<CoordinateCanvasOptions>): void;

  /** Reset view to fit all points */
  resetView(): void;

  /** Clean up resources */
  destroy(): void;
}
