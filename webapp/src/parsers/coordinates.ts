/**
 * Parser for area-visualizer coordinate format
 */

import { readFileAsText } from '@/file-access';
import type { FileSystemFileHandle } from '@/file-access';

/** Point type identifier */
export type PointType = 'S' | 'W' | 'w' | 'L' | 'Y' | 'N' | null;

/** Arrow direction */
export type ArrowDirection = 'L' | 'R' | 'U' | 'D' | null;

/** Parsed coordinate point */
export interface CoordinatePoint {
  x: number;
  y: number;
  type: PointType;
  arrowDir: ArrowDirection;
  /** Optional label for multi-city visualization */
  cityLabel?: string;
}

/** Parsed coordinates result */
export interface CoordinatesData {
  points: CoordinatePoint[];
  bounds: {
    minX: number;
    maxX: number;
    minY: number;
    maxY: number;
    width: number;
    height: number;
  };
}

/** Default colors for point types */
export const DEFAULT_POINT_COLORS: Record<string, string> = {
  'S': '#f44336',    // red
  'W': '#90caf9',    // light blue
  'w': '#1976d2',    // blue
  'L': '#a5d6a7',    // light green
  'Y': '#ffeb3b',    // yellow
  'N': '#000000',    // black
  'default': '#f44336', // red for unknown
};

/**
 * Parse a single line of coordinate data
 * Supports multiple formats:
 * - Space-separated: "prefix x,y,type,direction"
 * - Tab-separated (TSV): "prefix\tx,y,type,direction"
 */
function parseLine(line: string, cityLabel?: string): CoordinatePoint | null {
  const trimmed = line.trim();
  if (!trimmed) return null;

  // Try tab-separated first (TSV), then space-separated
  let parts = trimmed.split('\t');
  if (parts.length < 2) {
    parts = trimmed.split(' ');
  }
  if (parts.length < 2) return null;

  const coordPart = parts[1];
  const coordParts = coordPart.split(',');
  if (coordParts.length < 2) return null;

  // Parse x, y (handle "msg=" prefix if present)
  const xStr = coordParts[0].replace(/^msg=/, '');
  const x = parseInt(xStr, 10);
  const y = parseInt(coordParts[1], 10);

  if (isNaN(x) || isNaN(y)) return null;

  // Parse type and direction
  const type = (coordParts[2]?.trim() as PointType) || null;
  const arrowDir = (coordParts[3]?.trim() as ArrowDirection) || null;

  return { x, y, type, arrowDir, cityLabel };
}

/**
 * Parse content string into points
 */
function parseContent(content: string, cityLabel?: string): CoordinatePoint[] {
  const lines = content.split('\n');
  const points: CoordinatePoint[] = [];

  for (const line of lines) {
    const point = parseLine(line, cityLabel);
    if (point) {
      points.push(point);
    }
  }

  return points;
}

/**
 * Calculate bounds from points
 */
function calculateBounds(points: CoordinatePoint[]): CoordinatesData['bounds'] {
  if (points.length === 0) {
    return { minX: 0, maxX: 0, minY: 0, maxY: 0, width: 0, height: 0 };
  }

  const xCoords = points.map(p => p.x);
  const yCoords = points.map(p => p.y);

  const minX = Math.min(...xCoords);
  const maxX = Math.max(...xCoords);
  const minY = Math.min(...yCoords);
  const maxY = Math.max(...yCoords);

  return {
    minX,
    maxX,
    minY,
    maxY,
    width: maxX - minX,
    height: maxY - minY,
  };
}

/**
 * Load and parse coordinates from a file
 */
export async function loadCoordinates(
  fileHandle: FileSystemFileHandle,
  cityLabel?: string
): Promise<CoordinatesData> {
  const content = await readFileAsText(fileHandle);
  const points = parseContent(content, cityLabel);

  return {
    points,
    bounds: calculateBounds(points),
  };
}

/**
 * Load and merge coordinates from multiple files
 */
export async function loadMultipleCoordinates(
  files: Array<{ handle: FileSystemFileHandle; label: string }>
): Promise<CoordinatesData> {
  const allPoints: CoordinatePoint[] = [];

  for (const { handle, label } of files) {
    const content = await readFileAsText(handle);
    const points = parseContent(content, label);
    allPoints.push(...points);
  }

  return {
    points: allPoints,
    bounds: calculateBounds(allPoints),
  };
}

/**
 * Get arrow vector for rendering
 * Returns [startDx, startDy, endDx, endDy] relative to point
 */
export function getArrowVector(
  direction: ArrowDirection,
  startDist: number = 15,
  endDist: number = 5
): [number, number, number, number] | null {
  switch (direction) {
    case 'L': return [startDist, 0, endDist, 0];     // Coming from left
    case 'R': return [-startDist, 0, -endDist, 0];   // Coming from right
    case 'U': return [0, -startDist, 0, -endDist];   // Coming from up
    case 'D': return [0, startDist, 0, endDist];     // Coming from down
    default: return null;
  }
}
