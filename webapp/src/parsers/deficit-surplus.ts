/**
 * Parser for remaining-deficit.json and remaining-surplus.json
 */

import type { FileSystemDirectoryHandle } from '@/file-access';
import { readJsonFromDirectory } from '@/file-access';
import type { GoodsNameMap } from './texts';
import { resolveGoodName } from './texts';

/** Raw deficit/surplus entry from JSON */
interface RawDeficitSurplusEntry {
  Total: number;
  Areas: Array<{
    AreaName: string;
    Amount: number;
  }>;
}

/** Raw file format */
type RawDeficitSurplusFile = Record<string, RawDeficitSurplusEntry>;

/** Parsed area data */
export interface AreaAmount {
  areaName: string;
  amount: number;
}

/** Parsed deficit/surplus entry */
export interface DeficitSurplusEntry {
  goodId: string;
  goodName: string;
  total: number;
  areas: AreaAmount[];
}

/** Combined deficit/surplus data */
export interface DeficitSurplusData {
  deficit: DeficitSurplusEntry[];
  surplus: DeficitSurplusEntry[];
}

/**
 * Parse deficit or surplus file
 */
function parseDeficitSurplus(
  raw: RawDeficitSurplusFile | null,
  goodsNames: GoodsNameMap
): DeficitSurplusEntry[] {
  if (!raw) return [];

  return Object.entries(raw)
    .map(([goodId, entry]) => ({
      goodId,
      goodName: resolveGoodName(goodId, goodsNames),
      total: entry.Total,
      areas: entry.Areas.map(a => ({
        areaName: a.AreaName,
        amount: a.Amount,
      })),
    }))
    .sort((a, b) => b.total - a.total); // Sort by total descending
}

/**
 * Load and parse deficit/surplus data
 */
export async function loadDeficitSurplus(
  dirHandle: FileSystemDirectoryHandle,
  profileName: string,
  region: string = 'OW',
  goodsNames: GoodsNameMap = {}
): Promise<DeficitSurplusData> {
  const deficitPath = `TrRAt_${profileName}_${region}_remaining-deficit.json`;
  const surplusPath = `TrRAt_${profileName}_${region}_remaining-surplus.json`;

  const [deficitRaw, surplusRaw] = await Promise.all([
    readJsonFromDirectory<RawDeficitSurplusFile>(dirHandle, deficitPath),
    readJsonFromDirectory<RawDeficitSurplusFile>(dirHandle, surplusPath),
  ]);

  return {
    deficit: parseDeficitSurplus(deficitRaw, goodsNames),
    surplus: parseDeficitSurplus(surplusRaw, goodsNames),
  };
}

/**
 * Scan directory for profile names from deficit/surplus files
 * Returns unique profile names found in TrRAt_{ProfileName}_{Region}_remaining-*.json files
 */
export async function scanProfileNames(
  dirHandle: FileSystemDirectoryHandle
): Promise<string[]> {
  const { listFiles } = await import('@/file-access');
  const files = await listFiles(dirHandle, /^TrRAt_.+_(?:OW|NW|AR|EN|CT)_remaining-(?:deficit|surplus)\.json$/);

  const profileNamesSet = new Set<string>();

  for (const handle of files) {
    // Pattern: TrRAt_{ProfileName}_{Region}_remaining-{deficit|surplus}.json
    const match = handle.name.match(/^TrRAt_(.+?)_(?:OW|NW|AR|EN|CT)_remaining-(?:deficit|surplus)\.json$/);
    if (match) {
      profileNamesSet.add(match[1]);
    }
  }

  return Array.from(profileNamesSet).sort();
}

