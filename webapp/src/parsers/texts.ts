/**
 * Parser for texts.json - Good ID to name mapping
 */

import type { FileSystemDirectoryHandle } from '@/file-access';
import { readJsonFromDirectory, readJsonFromDirectoryResult, type Result, Ok } from '@/file-access';

export type GoodsNameMap = Record<string, string>;

/**
 * Load goods names from texts.json
 * Returns a map from good ID (string) to good name
 */
export async function loadGoodsNames(
  dirHandle: FileSystemDirectoryHandle,
  path: string = 'texts.json'
): Promise<GoodsNameMap> {
  const data = await readJsonFromDirectory<GoodsNameMap>(dirHandle, path);
  return data ?? {};
}

/**
 * Load goods names from texts.json (Result version)
 * Returns empty map if file not found (not an error case)
 */
export async function loadGoodsNamesResult(
  dirHandle: FileSystemDirectoryHandle,
  path: string = 'texts.json'
): Promise<Result<GoodsNameMap>> {
  const result = await readJsonFromDirectoryResult<GoodsNameMap>(dirHandle, path);

  // File not found is OK - return empty map
  if (!result.ok && result.error.name === 'FileNotFoundError') {
    return Ok({});
  }

  return result;
}

/**
 * Resolve a good ID to its name
 */
export function resolveGoodName(
  goodId: string | number,
  goodsNames: GoodsNameMap
): string {
  const id = String(goodId);
  return goodsNames[id] ?? `Unknown(${id})`;
}
