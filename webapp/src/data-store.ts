/**
 * DataStore - Central data layer that loads and parses all log files upfront
 *
 * This separates data parsing from visualization. Widgets receive
 * pre-parsed data from the DataStore instead of calling parsers directly.
 */

import type { FileSystemDirectoryHandle } from './file-access';
import type { GoodsNameMap } from './parsers/texts';
import type { TradeEntry } from './parsers/trades';
import type { DeficitSurplusData } from './parsers/deficit-surplus';
import type { ShipUsageResult } from './parsers/ship-logs';
import type { AreaFilesIndex } from './parsers/area-files';
import type { LogEntry } from './parsers/base-log';

import { loadGoodsNamesResult } from './parsers/texts';
import { loadTradesResult } from './parsers/trades';
import { loadDeficitSurplus, scanProfileNames } from './parsers/deficit-surplus';
import { loadShipUsage } from './parsers/ship-logs';
import { scanAreaFiles } from './parsers/area-files';
import { parseBaseLog } from './parsers/base-log';
import { readTextFromDirectory } from './file-access';

/**
 * Parsed data for all logs in the selected directory
 */
export interface ParsedData {
  // Global data
  goodsNames: GoodsNameMap;
  profileNames: string[];

  // Per-profile data
  trades: Map<string, TradeEntry[]>;
  deficitSurplus: Map<string, Map<string, DeficitSurplusData>>; // profile -> region -> data
  baseLogs: Map<string, LogEntry[]>; // profile -> log entries

  // Ship usage (global, not per-profile)
  shipUsage: ShipUsageResult;

  // Area files (global)
  areaFiles: AreaFilesIndex | null;
}

/**
 * Loading errors per data type
 */
export interface LoadingErrors {
  goodsNames?: string;
  profileNames?: string;
  trades?: Map<string, string>; // profile -> error
  deficitSurplus?: Map<string, Map<string, string>>; // profile -> region -> error
  baseLogs?: Map<string, string>; // profile -> error
  shipUsage?: string;
  areaFiles?: string;
}

/**
 * DataStore manages all parsed log data
 */
export class DataStore {
  private dirHandle: FileSystemDirectoryHandle;
  private data: ParsedData | null = null;
  private errors: LoadingErrors = {};
  private loading = false;

  constructor(dirHandle: FileSystemDirectoryHandle) {
    this.dirHandle = dirHandle;
  }

  /**
   * Load and parse all available log files
   */
  async load(): Promise<void> {
    if (this.loading) {
      throw new Error('Already loading');
    }

    this.loading = true;
    this.errors = {};

    try {
      // Initialize data structure
      const parsedData: ParsedData = {
        goodsNames: {},
        profileNames: [],
        trades: new Map(),
        deficitSurplus: new Map(),
        baseLogs: new Map(),
        shipUsage: { regular: { entries: [] }, hub: { entries: [] } },
        areaFiles: null,
      };

      // Load goods names (needed for other parsers)
      const goodsNamesResult = await loadGoodsNamesResult(this.dirHandle, 'texts.json');
      if (goodsNamesResult.ok) {
        parsedData.goodsNames = goodsNamesResult.value;
      } else {
        this.errors.goodsNames = goodsNamesResult.error.message;
      }

      // Load profile names
      try {
        parsedData.profileNames = await scanProfileNames(this.dirHandle);
      } catch (error) {
        this.errors.profileNames = error instanceof Error ? error.message : 'Unknown error';
      }

      // Load data for each profile
      const regions = ['OW', 'NW', 'AR', 'EN', 'CT'];

      for (const profileName of parsedData.profileNames) {
        // Load trades for this profile
        const tradesPath = `TrRAt_${profileName}_trade-executor-history.json`;
        const tradesResult = await loadTradesResult(this.dirHandle, tradesPath, parsedData.goodsNames);

        if (tradesResult.ok) {
          parsedData.trades.set(profileName, tradesResult.value);
        } else {
          if (!this.errors.trades) {
            this.errors.trades = new Map();
          }
          this.errors.trades.set(profileName, tradesResult.error.message);
        }

        // Load deficit/surplus for each region
        parsedData.deficitSurplus.set(profileName, new Map());

        for (const region of regions) {
          try {
            const deficitSurplusData = await loadDeficitSurplus(
              this.dirHandle,
              profileName,
              region,
              parsedData.goodsNames
            );
            parsedData.deficitSurplus.get(profileName)!.set(region, deficitSurplusData);
          } catch (error) {
            if (!this.errors.deficitSurplus) {
              this.errors.deficitSurplus = new Map();
            }
            if (!this.errors.deficitSurplus.has(profileName)) {
              this.errors.deficitSurplus.set(profileName, new Map());
            }
            this.errors.deficitSurplus.get(profileName)!.set(
              region,
              error instanceof Error ? error.message : 'Unknown error'
            );
          }
        }

        // Load base logs for this profile
        const baseLogPath = `TrRAt_${profileName}_base.log`;
        try {
          const baseLogContent = await readTextFromDirectory(this.dirHandle, baseLogPath);
          if (baseLogContent) {
            const logEntries = parseBaseLog(baseLogContent);
            parsedData.baseLogs.set(profileName, logEntries);
          }
        } catch (error) {
          if (!this.errors.baseLogs) {
            this.errors.baseLogs = new Map();
          }
          this.errors.baseLogs.set(
            profileName,
            error instanceof Error ? error.message : 'Unknown error'
          );
        }
      }

      // Load ship usage logs (global, not per-profile)
      try {
        parsedData.shipUsage = await loadShipUsage(this.dirHandle);
      } catch (error) {
        this.errors.shipUsage = error instanceof Error ? error.message : 'Unknown error';
      }

      // Load area files index (global)
      try {
        parsedData.areaFiles = await scanAreaFiles(this.dirHandle);
      } catch (error) {
        this.errors.areaFiles = error instanceof Error ? error.message : 'Unknown error';
      }

      this.data = parsedData;
    } finally {
      this.loading = false;
    }
  }

  /**
   * Get the raw directory handle (for widgets that need to load individual files)
   */
  getDirHandle(): FileSystemDirectoryHandle {
    return this.dirHandle;
  }

  /**
   * Check if data has been loaded
   */
  isLoaded(): boolean {
    return this.data !== null;
  }

  /**
   * Get goods names mapping
   */
  getGoodsNames(): GoodsNameMap {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.goodsNames;
  }

  /**
   * Get list of available profile names
   */
  getProfileNames(): string[] {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.profileNames;
  }

  /**
   * Get trades for a specific profile
   */
  getTrades(profileName: string): TradeEntry[] | null {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.trades.get(profileName) ?? null;
  }

  /**
   * Get deficit/surplus data for a specific profile and region
   */
  getDeficitSurplus(profileName: string, region: string): DeficitSurplusData | null {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.deficitSurplus.get(profileName)?.get(region) ?? null;
  }

  /**
   * Get base logs for a specific profile
   */
  getBaseLogs(profileName: string): LogEntry[] | null {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.baseLogs.get(profileName) ?? null;
  }

  /**
   * Get ship usage data
   */
  getShipUsage(): ShipUsageResult {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.shipUsage;
  }

  /**
   * Get area files index
   */
  getAreaFiles(): AreaFilesIndex | null {
    if (!this.data) throw new Error('Data not loaded');
    return this.data.areaFiles;
  }

  /**
   * Get loading errors
   */
  getErrors(): LoadingErrors {
    return this.errors;
  }

  /**
   * Check if there were any errors during loading
   */
  hasErrors(): boolean {
    return Object.keys(this.errors).length > 0;
  }
}
