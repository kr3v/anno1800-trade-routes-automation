/**
 * Parser for base.log files (TrRAt_*_base.log)
 *
 * This file contains parsers for different log line types in the base.log file.
 */

import {parseTimestamp} from './trades';

/** Common fields present in most log lines */
export interface BaseLogEntry {
    /** Original unparsed log line */
    raw: string;
    /** Parsed timestamp */
    timestamp: Date;
    /** Region (OW, NW, etc.) - optional */
    region?: string;
    /** Location in code (e.g., "Trade.Loop") - optional */
    loc?: string;
}

/** Area stock/request log line */
export interface AreaStockLogEntry extends BaseLogEntry {
    type: 'area_stock';
    /** Trade iteration type: 'regular' or 'hub' */
    tradeType: 'regular' | 'hub';
    /** Iteration ID that groups related trades */
    iteration: number;
    /** Area name (e.g., "n1 (h)", "c2") */
    areaName: string;
    /** Area ID number */
    areaId: number;
    /** Good/product name (e.g., "Wood", "Illuminated Script") */
    goodName: string;
    /** Current stock amount at the area */
    stock: number;
    /** In-flight stock (stock expected to arrive soon) */
    inFlightIn: number;
    /** Outgoing stock (stock expected to get moved soon) */
    inFlightOut: number;
    /** How much the area requests of this good */
    request: number;
    /** Reasons why this good is requested (e.g., ["Production/Brick Factory", "Population/Artisan Residence"]) */
    reasons?: string[];
}

/** Ship availability/status log line */
export interface ShipStatusLogEntry extends BaseLogEntry {
    type: 'ship_status';
    /** Trade iteration type: 'regular' or 'hub' - optional if not in iteration */
    tradeType?: 'regular' | 'hub';
    /** Iteration ID - optional if not in iteration */
    iteration?: number;
    /** Ship availability status */
    status: 'available' | 'stillMoving';
    /** Ship object ID */
    oid: number;
    /** Ship name (first part before '-') */
    shipName: string;
    /** Ship route (e.g., "TRA_NW", "TRA_OW") */
    route: string;
    /** Whether ship is currently moving */
    isMoving: boolean;
    /** Whether ship has cargo */
    hasCargo: boolean;
}

/** Ship count summary log line */
export interface ShipCountLogEntry extends BaseLogEntry {
    type: 'ship_count';
    /** Trade iteration type: 'regular' or 'hub' - optional */
    tradeType?: 'regular' | 'hub';
    /** Iteration ID - optional */
    iteration?: number;
    /** Type of count */
    countType: 'available' | 'stillMoving';
    /** Number of ships */
    count: number;
}

/** Tasks spawned log line */
export interface TasksSpawnedLogEntry extends BaseLogEntry {
    type: 'tasks_spawned';
    tradeType: 'regular' | 'hub';
    iteration: number;
    /** Number of async tasks spawned */
    tasksSpawned: number;
}

/** Still available ships log line */
export interface StillAvailableLogEntry extends BaseLogEntry {
    type: 'still_available';
    tradeType: 'regular' | 'hub';
    iteration: number;
    /** Ships still available */
    shipsAvailable: number;
    /** Requests still existing */
    requestsRemaining: number;
}

/** Trade order spawn log line */
export interface TradeOrderSpawnLogEntry extends BaseLogEntry {
    type: 'trade_spawn';
    tradeType: 'regular' | 'hub';
    iteration: number;
    /** Source area ID and name */
    areaSrc: {id: number; name: string};
    /** Destination area ID and name */
    areaDst: {id: number; name: string};
    /** Ship ID and name */
    ship: {id: number; name: string};
    /** Good ID and name */
    good: {id: number; name: string};
    /** Amount to trade */
    amount: number;
}

/** Trade execution progress log line */
export interface TradeExecutionLogEntry extends BaseLogEntry {
    type: 'trade_execution';
    tradeType: 'regular' | 'hub';
    iteration: number;
    areaSrc: {id: number; name: string};
    areaDst: {id: number; name: string};
    ship: {id: number; name: string};
    good: {id: number; name: string};
    amount: number;
    /** Execution stage */
    stage:
        | 'start'
        | 'before'
        | 'moving_to_source'
        | 'arrived_source'
        | 'loaded'
        | 'moving_to_destination'
        | 'arrived_destination'
        | 'completed';
    /** Additional data depending on stage */
    data?: {
        /** Stock levels before trade (before stage) */
        sourceStock?: number;
        destinationStock?: number;
        /** Coordinates for movement */
        x?: number;
        y?: number;
        /** Final trade results (completed stage) */
        unloaded?: number;
        srcBefore?: number;
        srcAfter?: number;
        dstBefore?: number;
        dstAfter?: number;
    };
}

/** Iteration start log line */
export interface IterationStartLogEntry extends BaseLogEntry {
    type: 'iteration_start';
    tradeType: 'regular' | 'hub';
    iteration: number;
}

/** Generic/unparsed log line */
export interface GenericLogEntry extends BaseLogEntry {
    type: 'generic';
}

/** Union type of all log entry types */
export type LogEntry =
    | AreaStockLogEntry
    | ShipStatusLogEntry
    | ShipCountLogEntry
    | TasksSpawnedLogEntry
    | StillAvailableLogEntry
    | TradeOrderSpawnLogEntry
    | TradeExecutionLogEntry
    | IterationStartLogEntry
    | GenericLogEntry;

/** Extract common fields from a log line */
function extractBaseFields(line: string): Partial<BaseLogEntry> {
    const base: Partial<BaseLogEntry> = {
        raw: line,
    };

    // Extract timestamp (always at the start)
    const timestampMatch = line.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z?)/);
    if (timestampMatch) {
        base.timestamp = parseTimestamp(timestampMatch[1]);
    }

    // Extract region
    const regionMatch = line.match(/region=(\w+)/);
    if (regionMatch) {
        base.region = regionMatch[1];
    }

    // Extract loc
    const locMatch = line.match(/loc=([\w.]+)/);
    if (locMatch) {
        base.loc = locMatch[1];
    }

    return base;
}

/** Extract area from format "ID (name)" */
function parseArea(areaStr: string): {id: number; name: string} | null {
    const match = areaStr.match(/^"?(\d+)\s*\((.+?)\)"?$/);
    if (!match) return null;
    return {
        id: parseInt(match[1], 10),
        name: match[2],
    };
}

/** Extract ship/good from format "ID (name)" */
function parseIdName(str: string): {id: number; name: string} | null {
    const match = str.match(/^"?(\d+)\s*\((.+?)\)"?$/);
    if (!match) return null;
    return {
        id: parseInt(match[1], 10),
        name: match[2],
    };
}

/**
 * Parse area stock log line
 * Format: Area <name> (id=<id>) <good> stock=<n> (+<in>) (-<out>) request=<n> (reasons=[...])
 * Examples:
 *   2025-12-11T21:46:02Z type=regular iteration=20251211214602 loc=Trade.Loop region=NW Area Tartagena (id=9155) Steel Beams stock=26 (+0) (-0) request=15
 *   2025-12-11T21:46:02Z type=regular iteration=20251211214602 loc=Trade.Loop region=NW Area n1_(h) (id=8323) Ponchos stock=301 (+0) (-150) request=90
 *   2025-12-12T01:09:54Z type=regular iteration=20251212010954 loc=Trade.Loop region=OW Area c1_(h) (id=8706) Pigs stock=3 (+0) (-0) request=200 (reasons=[Production/Rendering Works,Production/Slaughterhouse,Production/Restaurant: Archduke's Schnitzel])
 */
function parseAreaStock(line: string): AreaStockLogEntry | null {
    const pattern =
        /type=(?<tradeType>regular|hub)\s+iteration=(?<iteration>\d+)\s+.*?Area\s+(?<areaName>.+?)\s+\(id=(?<areaId>\d+)\)\s+(?<goodName>.+?)\s+stock=(?<stock>\d+)\s+\((?<inFlightIn>[+-]?\d+)\)\s+\((?<inFlightOut>[+-]?\d+)\)\s+request=(?<request>[\d.]+)/;
    const match = line.match(pattern);
    if (!match?.groups) return null;

    const {tradeType, iteration, areaName, areaId, goodName, stock, inFlightIn, inFlightOut, request} =
        match.groups;

    const base = extractBaseFields(line);

    // Parse numeric values and normalize -0 to 0
    const parsedInFlightIn = parseInt(inFlightIn, 10);
    const parsedInFlightOut = parseInt(inFlightOut, 10);

    // Parse reasons if present
    let reasons: string[] | undefined = undefined;
    const reasonsMatch = line.match(/\(reasons=\[([^\]]*)\]\)/);
    if (reasonsMatch) {
        const reasonsStr = reasonsMatch[1];
        if (reasonsStr) {
            // Split by comma, but be careful with commas inside reason names
            // For now, simple split should work since the format is well-defined
            reasons = reasonsStr.split(',').map(r => r.trim()).filter(r => r.length > 0);
        } else {
            reasons = [];
        }
    }

    return {
        ...base,
        type: 'area_stock',
        tradeType: tradeType as 'regular' | 'hub',
        iteration: parseInt(iteration, 10),
        areaName,
        areaId: parseInt(areaId, 10),
        goodName,
        stock: parseInt(stock, 10),
        inFlightIn: parsedInFlightIn === 0 ? 0 : parsedInFlightIn,
        inFlightOut: parsedInFlightOut === 0 ? 0 : parsedInFlightOut,
        request: parseFloat(request),
        reasons,
    } as AreaStockLogEntry;
}

/**
 * Parse ship status log line
 * Example: 2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 trade route automation ship -> available : oid=12884901972 name=1-sY-tH-2af route=TRA_NW isMoving=false hasCargo=false
 */
function parseShipStatus(line: string): ShipStatusLogEntry | null {
    const pattern =
        /trade route automation ship -> (available|stillMoving)\s*:\s*oid=(\d+)\s+name=(.+?)\s+route=(\S+)\s+isMoving=(true|false)\s+hasCargo=(true|false)/;
    const match = line.match(pattern);
    if (!match) return null;

    const base = extractBaseFields(line);

    // Extract ship name (first part before '-')
    const fullShipName = match[3];
    const shipName = fullShipName.split('-')[0];

    // Extract optional type and iteration
    const typeMatch = line.match(/type=(regular|hub)/);
    const iterMatch = line.match(/iteration=(\d+)/);

    return {
        ...base,
        type: 'ship_status',
        tradeType: typeMatch ? (typeMatch[1] as 'regular' | 'hub') : undefined,
        iteration: iterMatch ? parseInt(iterMatch[1], 10) : undefined,
        status: match[1] as 'available' | 'stillMoving',
        oid: parseInt(match[2], 10),
        shipName,
        route: match[4],
        isMoving: match[5] === 'true',
        hasCargo: match[6] === 'true',
    } as ShipStatusLogEntry;
}

/**
 * Parse ship count log line
 * Example: 2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 Total available trade route automation ships: 4
 */
function parseShipCount(line: string): ShipCountLogEntry | null {
    const pattern = /Total (available|still moving) trade route automation ships:\s*(\d+)/;
    const match = line.match(pattern);
    if (!match) return null;

    const base = extractBaseFields(line);

    // Extract optional type and iteration
    const typeMatch = line.match(/type=(regular|hub)/);
    const iterMatch = line.match(/iteration=(\d+)/);

    return {
        ...base,
        type: 'ship_count',
        tradeType: typeMatch ? (typeMatch[1] as 'regular' | 'hub') : undefined,
        iteration: iterMatch ? parseInt(iterMatch[1], 10) : undefined,
        countType: match[1] === 'available' ? 'available' : 'stillMoving',
        count: parseInt(match[2], 10),
    } as ShipCountLogEntry;
}

/**
 * Parse tasks spawned log line
 * Example: 2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=regular iteration=1765311369 Spawned 0 async tasks for trade route execution.
 */
function parseTasksSpawned(line: string): TasksSpawnedLogEntry | null {
    if (!line.includes('async tasks for trade route execution')) return null;

    const base = extractBaseFields(line);

    // Extract all key=value pairs
    const fields: Record<string, string> = {};
    const fieldRegex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;

    while ((match = fieldRegex.exec(line)) !== null) {
        const key = match[1];
        const value = match[2] !== undefined ? match[2] : match[3];
        fields[key] = value;
    }

    // Extract tasks count from text
    const tasksMatch = line.match(/Spawned\s+(\d+)\s+async tasks/);
    if (!tasksMatch || !fields.type || !fields.iteration) return null;

    if (fields.type !== 'regular' && fields.type !== 'hub') return null;

    return {
        ...base,
        type: 'tasks_spawned',
        tradeType: fields.type as 'regular' | 'hub',
        iteration: parseInt(fields.iteration, 10),
        tasksSpawned: parseInt(tasksMatch[1], 10),
    } as TasksSpawnedLogEntry;
}

/**
 * Parse still available ships log line
 * Example: 2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=regular iteration=1765311369 Still available ships: 4, still existing requests: 11
 */
function parseStillAvailable(line: string): StillAvailableLogEntry | null {
    if (!line.includes('Still available ships')) return null;

    const base = extractBaseFields(line);

    // Extract all key=value pairs
    const fields: Record<string, string> = {};
    const fieldRegex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;

    while ((match = fieldRegex.exec(line)) !== null) {
        const key = match[1];
        const value = match[2] !== undefined ? match[2] : match[3];
        fields[key] = value;
    }

    // Extract ships and requests from text
    const statsMatch = line.match(/Still available ships:\s*(\d+),\s*still existing requests:\s*(\d+)/);
    if (!statsMatch || !fields.type || !fields.iteration) return null;

    if (fields.type !== 'regular' && fields.type !== 'hub') return null;

    return {
        ...base,
        type: 'still_available',
        tradeType: fields.type as 'regular' | 'hub',
        iteration: parseInt(fields.iteration, 10),
        shipsAvailable: parseInt(statsMatch[1], 10),
        requestsRemaining: parseInt(statsMatch[2], 10),
    } as StillAvailableLogEntry;
}

/**
 * Parse trade order spawn log line
 * Example: 2025-12-09T22:11:46Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" amount=150 loc=Trade.Loop aSrc="9602 (c2)" region=OW Spawning trade order
 */
function parseTradeSpawn(line: string): TradeOrderSpawnLogEntry | null {
    if (!line.includes('Spawning trade order')) return null;

    const base = extractBaseFields(line);

    // Extract all key=value pairs into a map (order-independent)
    // Values are quoted if they contain spaces, unquoted otherwise
    const fields: Record<string, string> = {};
    const fieldRegex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;

    while ((match = fieldRegex.exec(line)) !== null) {
        const key = match[1];
        const value = match[2] !== undefined ? match[2] : match[3];
        fields[key] = value;
    }

    // Check required fields exist
    if (!fields.type || !fields.iteration || !fields.aSrc || !fields.aDst ||
        !fields.ship || !fields.good || !fields.amount) {
        return null;
    }

    // Validate type
    if (fields.type !== 'regular' && fields.type !== 'hub') return null;

    const areaSrc = parseArea(fields.aSrc);
    const areaDst = parseArea(fields.aDst);
    const ship = parseIdName(fields.ship);
    const good = parseIdName(fields.good);

    if (!areaSrc || !areaDst || !ship || !good) return null;

    // Extract ship name (first part)
    ship.name = ship.name.split('-')[0];

    return {
        ...base,
        type: 'trade_spawn',
        tradeType: fields.type as 'regular' | 'hub',
        iteration: parseInt(fields.iteration, 10),
        areaSrc,
        areaDst,
        ship,
        good,
        amount: parseInt(fields.amount, 10),
    } as TradeOrderSpawnLogEntry;
}

/**
 * Parse trade execution log line
 * Example: 2025-12-09T22:12:22Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Loaded 150 total units; area src: 494 -> 344; moving to dst area (x=523 y=1578)
 */
function parseTradeExecution(line: string): TradeExecutionLogEntry | null {
    if (!line.includes('TradeExecutor._ExecuteTradeOrderWithShip')) return null;

    const base = extractBaseFields(line);

    // Extract all key=value pairs into a map (order-independent)
    const fields: Record<string, string> = {};
    const fieldRegex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;

    while ((match = fieldRegex.exec(line)) !== null) {
        const key = match[1];
        const value = match[2] !== undefined ? match[2] : match[3];
        fields[key] = value;
    }

    // Check required fields exist
    if (!fields.type || !fields.iteration || !fields.aSrc || !fields.aDst ||
        !fields.ship || !fields.good || !fields.amount) {
        return null;
    }

    // Validate type
    if (fields.type !== 'regular' && fields.type !== 'hub') return null;

    const areaSrc = parseArea(fields.aSrc);
    const areaDst = parseArea(fields.aDst);
    const ship = parseIdName(fields.ship);
    const good = parseIdName(fields.good);

    if (!areaSrc || !areaDst || !ship || !good) return null;

    // Extract ship name (first part)
    ship.name = ship.name.split('-')[0];

    // Determine stage and extract data
    let stage: TradeExecutionLogEntry['stage'];
    let data: TradeExecutionLogEntry['data'] = {};

    if (line.includes(' start')) {
        stage = 'start';
    } else if (line.includes('before: source =')) {
        stage = 'before';
        const beforeMatch = line.match(/before: source = (\d+), destination = (\d+)/);
        if (beforeMatch) {
            data.sourceStock = parseInt(beforeMatch[1], 10);
            data.destinationStock = parseInt(beforeMatch[2], 10);
        }
    } else if (line.includes('Moving ship') && line.includes('to source area')) {
        stage = 'moving_to_source';
        const coordMatch = line.match(/\(x=(\d+),\s*y=(\d+)\)/);
        if (coordMatch) {
            data.x = parseInt(coordMatch[1], 10);
            data.y = parseInt(coordMatch[2], 10);
        }
    } else if (line.includes('arrived at source area')) {
        stage = 'arrived_source';
    } else if (line.includes('Loaded') && line.includes('total units')) {
        stage = 'loaded';
        const loadedMatch = line.match(/Loaded (\d+) total units; area src: (\d+) -> (\d+)/);
        const coordMatch = line.match(/\(x=(\d+)\s+y=(\d+)\)/);
        if (loadedMatch) {
            data.unloaded = parseInt(loadedMatch[1], 10);
            data.srcBefore = parseInt(loadedMatch[2], 10);
            data.srcAfter = parseInt(loadedMatch[3], 10);
        }
        if (coordMatch) {
            data.x = parseInt(coordMatch[1], 10);
            data.y = parseInt(coordMatch[2], 10);
        }
    } else if (line.includes('arrived at destination area')) {
        stage = 'arrived_destination';
    } else if (line.includes('Trade order completed')) {
        stage = 'completed';
        const completedMatch = line.match(
            /unloaded=(\d+); src=\((\d+) -> (\d+)\); dst=\((\d+) -> (\d+)\)/
        );
        if (completedMatch) {
            data.unloaded = parseInt(completedMatch[1], 10);
            data.srcBefore = parseInt(completedMatch[2], 10);
            data.srcAfter = parseInt(completedMatch[3], 10);
            data.dstBefore = parseInt(completedMatch[4], 10);
            data.dstAfter = parseInt(completedMatch[5], 10);
        }
    } else {
        return null; // Unknown stage
    }

    return {
        ...base,
        type: 'trade_execution',
        tradeType: fields.type as 'regular' | 'hub',
        iteration: parseInt(fields.iteration, 10),
        areaSrc,
        areaDst,
        ship,
        good,
        amount: parseInt(fields.amount, 10),
        stage,
        data,
    } as TradeExecutionLogEntry;
}

/**
 * Parse iteration start log line
 * Example: 2025-12-09T22:06:21Z region=OW loc=Trade.Loop type=regular iteration=1765310781 start at 2025-12-09 22:06:21 time
 */
function parseIterationStart(line: string): IterationStartLogEntry | null {
    if (!line.includes('start at')) return null;

    const base = extractBaseFields(line);

    // Extract all key=value pairs
    const fields: Record<string, string> = {};
    const fieldRegex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;

    while ((match = fieldRegex.exec(line)) !== null) {
        const key = match[1];
        const value = match[2] !== undefined ? match[2] : match[3];
        fields[key] = value;
    }

    if (!fields.type || !fields.iteration) return null;

    if (fields.type !== 'regular' && fields.type !== 'hub') return null;

    return {
        ...base,
        type: 'iteration_start',
        tradeType: fields.type as 'regular' | 'hub',
        iteration: parseInt(fields.iteration, 10),
    } as IterationStartLogEntry;
}

/**
 * Parse a single log line into a LogEntry
 */
export function parseLogLine(line: string): LogEntry {
    // Skip empty lines
    if (!line.trim()) {
        const base = extractBaseFields(line);
        return {...base, type: 'generic'} as GenericLogEntry;
    }

    // Try each parser in order of specificity
    let parsed: LogEntry | null;

    parsed = parseAreaStock(line);
    if (parsed) return parsed;

    parsed = parseShipStatus(line);
    if (parsed) return parsed;

    parsed = parseShipCount(line);
    if (parsed) return parsed;

    parsed = parseTasksSpawned(line);
    if (parsed) return parsed;

    parsed = parseStillAvailable(line);
    if (parsed) return parsed;

    parsed = parseTradeSpawn(line);
    if (parsed) return parsed;

    parsed = parseTradeExecution(line);
    if (parsed) return parsed;

    parsed = parseIterationStart(line);
    if (parsed) return parsed;

    // If nothing matched, return generic
    const base = extractBaseFields(line);
    return {...base, type: 'generic'} as GenericLogEntry;
}

/**
 * Parse entire log file content
 */
export function parseBaseLog(content: string): LogEntry[] {
    const lines = content.split('\n');
    return lines.map(parseLogLine).filter((entry) => entry.timestamp !== undefined);
}
