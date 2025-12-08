/**
 * Parser for trade-execute-iteration.*.log files
 */

import type {FileSystemDirectoryHandle} from '@/file-access';
import {listFiles, readFileAsText} from '@/file-access';
import {parseTimestamp} from './trades';

/** Parsed log entry */
export interface ShipLogEntry {
    timestamp: Date;
    shipsAvailable: number;
    tasksSpawned: number;
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
 * Parse a single log file content
 */
function parseLogContent(content: string): ShipLogEntry | null {
    // Extract timestamp
    const timestampMatch = content.match(/(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z?)/);
    if (!timestampMatch) return null;

    const timestamp = parseTimestamp(timestampMatch[1]);

    // Extract ships available
    const shipsMatch = content.match(/Total available trade route automation ships:\s*(\d+)/);
    const shipsAvailable = shipsMatch ? parseInt(shipsMatch[1], 10) : 0;

    // Extract tasks spawned
    const tasksMatch = content.match(/Spawned\s+(\d+)\s+async tasks for trade route execution/);
    const tasksSpawned = tasksMatch ? parseInt(tasksMatch[1], 10) : 0;

    return {timestamp, shipsAvailable, tasksSpawned};
}

/**
 * Load and parse ship usage logs from a directory
 */
export async function loadShipUsage(
    dirHandle: FileSystemDirectoryHandle,
    // region: string = 'OW'
): Promise<ShipUsageResult> {
    const logDir = dirHandle;

    if (!logDir) {
        return {
            regular: {entries: []},
            hub: {entries: []},
        };
    }

    // List all log files
    const logPattern = /^TrRAt_([a-zA-Z0-9_\s-]+?)_trade-execute-iteration\.log(\.hub)?$/;
    const logFiles = await listFiles(logDir, logPattern);

    // Parse log files
    const regularEntries: ShipLogEntry[] = [];
    const hubEntries: ShipLogEntry[] = [];

    for (const fileHandle of logFiles) {
        const content = await readFileAsText(fileHandle);
        const entry = parseLogContent(content);

        if (entry) {
            if (fileHandle.name.endsWith('.hub')) {
                hubEntries.push(entry);
            } else {
                regularEntries.push(entry);
            }
        }
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
