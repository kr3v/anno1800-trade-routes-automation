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
  /** Optional region identifier (e.g., OW, NW) */
  region?: string;
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
 * - Log format: "2025-12-09T20:33:09Z loc=Trade.Loop region=OW 360,1500,L"
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

  // Detect log format: starts with ISO timestamp (YYYY-MM-DDTHH:MM:SSZ)
  const isLogFormat = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/.test(parts[0]);

  if (isLogFormat) {
    // New log format: "timestamp loc=... region=... x,y,type"
    let region: string | undefined;
    let coordPart: string | undefined;

    // Find region and coordinates parts
    for (const part of parts) {
      if (part.startsWith('region=')) {
        region = part.substring(7); // Extract region value
      } else if (part.includes(',')) {
        // This is likely the coordinates part
        coordPart = part;
      }
    }

    if (!coordPart) return null;

    const coordParts = coordPart.split(',');
    if (coordParts.length < 2) return null;

    const x = parseInt(coordParts[0], 10);
    const y = parseInt(coordParts[1], 10);

    if (isNaN(x) || isNaN(y)) return null;

    // In log format, third part is the type (not arrow direction)
    const type = (coordParts[2]?.trim() as PointType) || null;

    return { x, y, type, arrowDir: null, cityLabel, region };
  } else {
    // Original format: "prefix x,y,type,direction"
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
