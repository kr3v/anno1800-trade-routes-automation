/**
 * Parser for base.log files
 */

import type {FileSystemDirectoryHandle} from '@/file-access';
import {listFiles, readFileAsText} from '@/file-access';
import {parseBaseLog, type ShipCountLogEntry, type TasksSpawnedLogEntry} from './base-log';

/** Parsed log entry */
export interface ShipLogEntry {
    timestamp: Date;
    shipsAvailable: number;
    tasksSpawned: number;
    region?: string;
}

/** Ship usage data for a mode (regular or hub) */
export interface ShipUsageData {
    entries: ShipLogEntry[];
}

/** Combined ship usage data */
export interface ShipUsageResult {
    regular: ShipUsageData;
    hub: ShipUsageData;
}

/**
 * Parse base.log content for ship usage data
 */
function parseLogContent(content: string): {regular: ShipLogEntry[]; hub: ShipLogEntry[]} {
    const entries = parseBaseLog(content);

    // Group data by (iteration, region) pair to handle cases where
    // the same iteration number is used across multiple regions
    type MapKey = string; // Format: "iteration:region"
    const regularData = new Map<MapKey, {timestamp: Date; ships?: number; tasks?: number; region: string; iteration: number}>();
    const hubData = new Map<MapKey, {timestamp: Date; ships?: number; tasks?: number; region: string; iteration: number}>();

    for (const entry of entries) {
        if (entry.type === 'ship_count') {
            const shipCount = entry as ShipCountLogEntry;
            if (shipCount.iteration && shipCount.countType === 'available') {
                const map = shipCount.tradeType === 'hub' ? hubData : regularData;
                const key = `${shipCount.iteration}:${shipCount.region || 'unknown'}`;
                if (!map.has(key)) {
                    map.set(key, {
                        timestamp: shipCount.timestamp!,
                        region: shipCount.region || 'unknown',
                        iteration: shipCount.iteration
                    });
                }
                map.get(key)!.ships = shipCount.count;
            }
        } else if (entry.type === 'tasks_spawned') {
            const tasksSpawned = entry as TasksSpawnedLogEntry;
            const map = tasksSpawned.tradeType === 'hub' ? hubData : regularData;
            const key = `${tasksSpawned.iteration}:${tasksSpawned.region || 'unknown'}`;
            if (!map.has(key)) {
                map.set(key, {
                    timestamp: tasksSpawned.timestamp!,
                    region: tasksSpawned.region || 'unknown',
                    iteration: tasksSpawned.iteration
                });
            }
            map.get(key)!.tasks = tasksSpawned.tasksSpawned;
        }
    }

    // Convert to entries array
    const regularEntries: ShipLogEntry[] = [];
    const hubEntries: ShipLogEntry[] = [];

    for (const [_key, data] of regularData.entries()) {
        if (data.ships !== undefined || data.tasks !== undefined) {
            regularEntries.push({
                timestamp: data.timestamp,
                shipsAvailable: data.ships ?? 0,
                tasksSpawned: data.tasks ?? 0,
                region: data.region,
            });
        }
    }

    for (const [_key, data] of hubData.entries()) {
        if (data.ships !== undefined || data.tasks !== undefined) {
            hubEntries.push({
                timestamp: data.timestamp,
                shipsAvailable: data.ships ?? 0,
                tasksSpawned: data.tasks ?? 0,
                region: data.region,
            });
        }
    }

    // Sort by timestamp
    regularEntries.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
    hubEntries.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    return {regular: regularEntries, hub: hubEntries};
}

/**
 * Load and parse ship usage logs from a directory
 */
export async function loadShipUsage(
    dirHandle: FileSystemDirectoryHandle,
): Promise<ShipUsageResult> {
    const logDir = dirHandle;

    if (!logDir) {
        return {
            regular: {entries: []},
            hub: {entries: []},
        };
    }

    // List all base.log files
    const logPattern = /^TrRAt_([a-zA-Z0-9_\s-]+?)_base\.log$/;
    const logFiles = await listFiles(logDir, logPattern);

    // Parse log files
    const regularEntries: ShipLogEntry[] = [];
    const hubEntries: ShipLogEntry[] = [];

    for (const fileHandle of logFiles) {
        const content = await readFileAsText(fileHandle);
        const {regular, hub} = parseLogContent(content);
        regularEntries.push(...regular);
        hubEntries.push(...hub);
    }

    // Sort by timestamp
    regularEntries.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());
    hubEntries.sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

    return {
        regular: {entries: regularEntries},
        hub: {entries: hubEntries},
    };
}

/**
 * Calculate moving average for a series
 */
export function calculateMovingAverage(
    values: number[],
    windowSize: number
): number[] {
    if (values.length === 0 || windowSize <= 0) return values;

    return values.map((_, i) => {
        const start = Math.max(0, i - Math.floor(windowSize / 2));
        const end = Math.min(values.length, i + Math.floor(windowSize / 2) + 1);
        const window = values.slice(start, end);
        return window.reduce((a, b) => a + b, 0) / window.length;
    });
}

/**
 * Calculate summary statistics
 */
export function calculateStats(entries: ShipLogEntry[]): {
    avgShips: number;
    avgTasks: number;
    count: number;
} {
    if (entries.length === 0) {
        return {avgShips: 0, avgTasks: 0, count: 0};
    }

    const totalShips = entries.reduce((sum, e) => sum + e.shipsAvailable, 0);
    const totalTasks = entries.reduce((sum, e) => sum + e.tasksSpawned, 0);

    return {
        avgShips: totalShips / entries.length,
        avgTasks: totalTasks / entries.length,
        count: entries.length,
    };
}
