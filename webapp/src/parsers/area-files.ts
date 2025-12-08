/**
 * Parser for area scan file discovery and metadata extraction
 */

import type { FileSystemDirectoryHandle, FileSystemFileHandle } from '@/file-access';
import { listFiles } from '@/file-access';

/** Region codes and their display names */
export const REGIONS: Record<string, string> = {
  'OW': 'Old World',
  'NW': 'New World',
  'AR': 'Arctic',
  'EN': 'Enbesa',
  'CT': 'Cape Trelawney',
};

/** Parsed area file metadata */
export interface AreaFileInfo {
  handle: FileSystemFileHandle;
  fileName: string;
  gameName: string;
  cityName: string;
  region: string | null;  // OW, NW, AR, EN, CT or null if unknown
  isHub: boolean;  // (h) suffix
}

/** Grouped area files */
export interface AreaFilesIndex {
  /** All unique game names */
  gameNames: string[];
  /** Files grouped by game name */
  byGame: Map<string, AreaFileInfo[]>;
  /** Files grouped by game name -> region */
  byGameAndRegion: Map<string, Map<string, AreaFileInfo[]>>;
}

/**
 * Extract region from the first line of a TSV file
 * Format: "2025-12-09T20:33:09Z loc=Trade.Loop region=OW 360,1500,L"
 */
async function extractRegionFromFile(fileHandle: FileSystemFileHandle): Promise<string | null> {
  try {
    const file = await fileHandle.getFile();
    const text = await file.text();
    const firstLine = text.split('\n')[0];

    // Look for "region=XX" in the line
    const parts = firstLine.split(' ');
    for (const part of parts) {
      if (part.startsWith('region=')) {
        return part.substring(7); // Extract region value
      }
    }
  } catch (error) {
    // If we can't read the file, return null
    console.warn(`Failed to extract region from ${fileHandle.name}:`, error);
  }
  return null;
}

/**
 * Parse area scan filename
 * Pattern: TrRAt_{GameName}_area_scan_{CityName}.tsv
 *          TrRAt_{GameName}_area_scan_{CityName}_(h).tsv (hub)
 */
function parseAreaFileName(fileName: string): { gameName: string; cityName: string; isHub: boolean } | null {
  // Match pattern: TrRAt_{gameName}_area_scan_{cityName}.tsv or TrRAt_{gameName}_area_scan_{cityName}_(h).tsv
  const match = fileName.match(/^TrRAt_(.+?)_area_scan_(.+?)(?:_\(h\))?\.tsv$/);
  if (!match) return null;

  const gameName = match[1];
  let cityName = match[2];
  const isHub = fileName.includes('_(h)');

  return { gameName, cityName, isHub };
}

/**
 * Scan directory for area scan files and build index
 */
export async function scanAreaFiles(
  dirHandle: FileSystemDirectoryHandle
): Promise<AreaFilesIndex> {
  const files = await listFiles(dirHandle, /^TrRAt_.+_area_scan_.+\.tsv$/);

  const byGame = new Map<string, AreaFileInfo[]>();
  const byGameAndRegion = new Map<string, Map<string, AreaFileInfo[]>>();
  const gameNamesSet = new Set<string>();

  for (const handle of files) {
    const parsed = parseAreaFileName(handle.name);
    if (!parsed) continue;

    // Extract region from first line of file
    const region = await extractRegionFromFile(handle);
    const info: AreaFileInfo = {
      handle,
      fileName: handle.name,
      gameName: parsed.gameName,
      cityName: parsed.cityName,
      region,
      isHub: parsed.isHub,
    };

    gameNamesSet.add(parsed.gameName);

    // Group by game
    if (!byGame.has(parsed.gameName)) {
      byGame.set(parsed.gameName, []);
    }
    byGame.get(parsed.gameName)!.push(info);

    // Group by game and region
    if (!byGameAndRegion.has(parsed.gameName)) {
      byGameAndRegion.set(parsed.gameName, new Map());
    }
    const regionMap = byGameAndRegion.get(parsed.gameName)!;
    const regionKey = region ?? 'unknown';
    if (!regionMap.has(regionKey)) {
      regionMap.set(regionKey, []);
    }
    regionMap.get(regionKey)!.push(info);
  }

  // Sort game names
  const gameNames = [...gameNamesSet].sort();

  // Sort files within each group by city name
  for (const files of byGame.values()) {
    files.sort((a, b) => a.cityName.localeCompare(b.cityName));
  }

  return { gameNames, byGame, byGameAndRegion };
}

/**
 * Get unique regions for a game
 */
export function getRegionsForGame(index: AreaFilesIndex, gameName: string): string[] {
  const regionMap = index.byGameAndRegion.get(gameName);
  if (!regionMap) return [];
  return [...regionMap.keys()].sort();
}

/**
 * Get cities for a game and optional region filter
 */
export function getCitiesForGameAndRegion(
  index: AreaFilesIndex,
  gameName: string,
  region: string | null
): AreaFileInfo[] {
  if (region) {
    const regionMap = index.byGameAndRegion.get(gameName);
    return regionMap?.get(region) ?? [];
  }
  return index.byGame.get(gameName) ?? [];
}

/**
 * Get display name for city (strip region prefix)
 */
export function getCityDisplayName(info: AreaFileInfo): string {
  let name = info.cityName;
  if (info.region) {
    name = name.replace(`${info.region}_`, '');
  }
  if (info.isHub) {
    name += ' (hub)';
  }
  return name;
}
