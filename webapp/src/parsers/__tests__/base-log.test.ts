/**
 * Unit tests for base-log.ts parser
 */

import {describe, it, expect} from 'vitest';
import {
    parseLogLine,
    type AreaStockLogEntry,
    type ShipStatusLogEntry,
    type ShipCountLogEntry,
    type TasksSpawnedLogEntry,
    type StillAvailableLogEntry,
    type TradeOrderSpawnLogEntry,
    type TradeExecutionLogEntry,
    type IterationStartLogEntry,
} from '../base-log';

describe('base-log parser', () => {
    describe('parseAreaStock', () => {
        const testCases: Array<{name: string; input: string; expected: Partial<AreaStockLogEntry>}> = [
            {
                name: 'basic area stock',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 Area Tartagena (id=9155) Work Clothes stock=0 (+0) (-0) request=75',
                expected: {
                    type: 'area_stock',
                    tradeType: 'hub',
                    iteration: 1765311369,
                    region: 'NW',
                    loc: 'Trade.Loop',
                    areaName: 'Tartagena',
                    areaId: 9155,
                    goodName: 'Work Clothes',
                    stock: 0,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 75,
                },
            },
            {
                name: 'area with underscore and parentheses',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 Area n1_(h) (id=8323) Illuminated Script stock=0 (+0) (-0) request=405.0',
                expected: {
                    type: 'area_stock',
                    tradeType: 'hub',
                    iteration: 1765311369,
                    areaName: 'n1_(h)',
                    areaId: 8323,
                    goodName: 'Illuminated Script',
                    stock: 0,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 405.0,
                },
            },
            {
                name: 'with incoming stock',
                input: '2025-12-09T22:10:44Z region=OW loc=Trade.Loop type=hub iteration=1765311043 Area c1_(h) (id=8706) Work Clothes stock=480 (+150) (-0) request=1035.0',
                expected: {
                    type: 'area_stock',
                    areaName: 'c1_(h)',
                    areaId: 8706,
                    goodName: 'Work Clothes',
                    stock: 480,
                    inFlightIn: 150,
                    inFlightOut: 0,
                    request: 1035.0,
                },
            },
            {
                name: 'with both in-flight and outgoing stock',
                input: '2025-12-11T21:46:02Z type=regular iteration=20251211214602 loc=Trade.Loop region=NW Area Tartagena (id=9155) Steel Beams stock=26 (+0) (-0) request=15',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251211214602,
                    region: 'NW',
                    loc: 'Trade.Loop',
                    areaName: 'Tartagena',
                    areaId: 9155,
                    goodName: 'Steel Beams',
                    stock: 26,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 15,
                },
            },
            {
                name: 'with outgoing stock',
                input: '2025-12-11T21:46:02Z type=regular iteration=20251211214602 loc=Trade.Loop region=NW Area n1_(h) (id=8323) Ponchos stock=301 (+0) (-150) request=90',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251211214602,
                    areaName: 'n1_(h)',
                    areaId: 8323,
                    goodName: 'Ponchos',
                    stock: 301,
                    inFlightIn: 0,
                    inFlightOut: -150,
                    request: 90,
                },
            },
            {
                name: 'with incoming stock (non-zero)',
                input: '2025-12-11T21:46:17Z type=regular iteration=20251211214617 loc=Trade.Loop region=OW Area c1_(h) (id=8706) Windows stock=241 (+264) (-0) request=500',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251211214617,
                    areaName: 'c1_(h)',
                    areaId: 8706,
                    goodName: 'Windows',
                    stock: 241,
                    inFlightIn: 264,
                    inFlightOut: 0,
                    request: 500,
                },
            },
            {
                name: 'with reasons (single category)',
                input: '2025-12-12T01:09:54Z type=regular iteration=20251212010954 loc=Trade.Loop region=OW Area c1_(h) (id=8706) Reinforced Concrete stock=251 (+0) (-0) request=200 (reasons=[Construction])',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251212010954,
                    areaName: 'c1_(h)',
                    areaId: 8706,
                    goodName: 'Reinforced Concrete',
                    stock: 251,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 200,
                    reasons: ['Construction'],
                },
            },
            {
                name: 'with reasons (multiple categories)',
                input: '2025-12-12T01:09:54Z type=regular iteration=20251212010954 loc=Trade.Loop region=OW Area c1_(h) (id=8706) Pigs stock=3 (+0) (-0) request=200 (reasons=[Production/Rendering Works,Production/Slaughterhouse,Production/Restaurant: Archduke\'s Schnitzel])',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251212010954,
                    areaName: 'c1_(h)',
                    areaId: 8706,
                    goodName: 'Pigs',
                    stock: 3,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 200,
                    reasons: ['Production/Rendering Works', 'Production/Slaughterhouse', 'Production/Restaurant: Archduke\'s Schnitzel'],
                },
            },
            {
                name: 'with reasons (population)',
                input: '2025-12-12T01:09:54Z type=regular iteration=20251212010954 loc=Trade.Loop region=OW Area c1_(h) (id=8706) Fish stock=541 (+0) (-0) request=200 (reasons=[Population/Worker Residence,Population/Farmer Residence])',
                expected: {
                    type: 'area_stock',
                    tradeType: 'regular',
                    iteration: 20251212010954,
                    areaName: 'c1_(h)',
                    areaId: 8706,
                    goodName: 'Fish',
                    stock: 541,
                    inFlightIn: 0,
                    inFlightOut: 0,
                    request: 200,
                    reasons: ['Population/Worker Residence', 'Population/Farmer Residence'],
                },
            },
        ];

        testCases.forEach(({name, input, expected}) => {
            it(name, () => {
                const result = parseLogLine(input);
                expect(result.type).toBe('area_stock');
                Object.entries(expected).forEach(([key, value]) => {
                    expect(result).toHaveProperty(key, value);
                });
                expect(result.raw).toBe(input);
            });
        });
    });

    describe('parseShipStatus', () => {
        const testCases: Array<{name: string; input: string; expected: Partial<ShipStatusLogEntry>}> = [
            {
                name: 'available ship',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 trade route automation ship -> available : oid=12884901972 name=1-sY-tH-2af route=TRA_NW isMoving=false hasCargo=false',
                expected: {
                    type: 'ship_status',
                    tradeType: 'hub',
                    iteration: 1765311369,
                    status: 'available',
                    oid: 12884901972,
                    shipName: '1',
                    route: 'TRA_NW',
                    isMoving: false,
                    hasCargo: false,
                },
            },
            {
                name: 'still moving ship',
                input: '2025-12-09T22:06:20Z region=OW loc=Trade.Loop trade route automation ship -> stillMoving : oid=8589942578 name=Z1-fu-r8-2uS route=TRA_OW isMoving=true hasCargo=false',
                expected: {
                    type: 'ship_status',
                    status: 'stillMoving',
                    oid: 8589942578,
                    shipName: 'Z1',
                    route: 'TRA_OW',
                    isMoving: true,
                    hasCargo: false,
                },
            },
            {
                name: 'ship with cargo',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 trade route automation ship -> available : oid=12884902329 name=Q1-sY-tH-2af route=TRA_NW isMoving=false hasCargo=true',
                expected: {
                    type: 'ship_status',
                    shipName: 'Q1',
                    hasCargo: true,
                },
            },
        ];

        testCases.forEach(({name, input, expected}) => {
            it(name, () => {
                const result = parseLogLine(input);
                expect(result.type).toBe('ship_status');
                Object.entries(expected).forEach(([key, value]) => {
                    expect(result).toHaveProperty(key, value);
                });
            });
        });
    });

    describe('parseShipCount', () => {
        const testCases: Array<{name: string; input: string; expected: Partial<ShipCountLogEntry>}> = [
            {
                name: 'available ships count',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 Total available trade route automation ships: 4',
                expected: {
                    type: 'ship_count',
                    tradeType: 'hub',
                    iteration: 1765311369,
                    countType: 'available',
                    count: 4,
                },
            },
            {
                name: 'still moving ships count',
                input: '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=hub iteration=1765311369 Total still moving trade route automation ships: 0',
                expected: {
                    type: 'ship_count',
                    countType: 'stillMoving',
                    count: 0,
                },
            },
        ];

        testCases.forEach(({name, input, expected}) => {
            it(name, () => {
                const result = parseLogLine(input);
                expect(result.type).toBe('ship_count');
                Object.entries(expected).forEach(([key, value]) => {
                    expect(result).toHaveProperty(key, value);
                });
            });
        });
    });

    describe('parseTasksSpawned', () => {
        it('should parse tasks spawned', () => {
            const input =
                '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=regular iteration=1765311369 Spawned 0 async tasks for trade route execution.';
            const result = parseLogLine(input) as TasksSpawnedLogEntry;
            expect(result.type).toBe('tasks_spawned');
            expect(result.tradeType).toBe('regular');
            expect(result.iteration).toBe(1765311369);
            expect(result.tasksSpawned).toBe(0);
        });
    });

    describe('parseStillAvailable', () => {
        it('should parse still available ships', () => {
            const input =
                '2025-12-09T22:16:09Z region=NW loc=Trade.Loop type=regular iteration=1765311369 Still available ships: 4, still existing requests: 11';
            const result = parseLogLine(input) as StillAvailableLogEntry;
            expect(result.type).toBe('still_available');
            expect(result.tradeType).toBe('regular');
            expect(result.iteration).toBe(1765311369);
            expect(result.shipsAvailable).toBe(4);
            expect(result.requestsRemaining).toBe(11);
        });
    });

    describe('parseTradeSpawn', () => {
        it('should parse trade order spawn', () => {
            const input =
                '2025-12-09T22:11:46Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" amount=150 loc=Trade.Loop aSrc="9602 (c2)" region=OW Spawning trade order';
            const result = parseLogLine(input) as TradeOrderSpawnLogEntry;
            expect(result.type).toBe('trade_spawn');
            expect(result.tradeType).toBe('hub');
            expect(result.iteration).toBe(1765311106);
            expect(result.areaSrc).toEqual({id: 9602, name: 'c2'});
            expect(result.areaDst).toEqual({id: 8706, name: 'c1 (h)'});
            expect(result.ship).toEqual({id: 8589938023, name: 'Q1'});
            expect(result.good).toEqual({id: 120008, name: 'Wood'});
            expect(result.amount).toBe(150);
            expect(result.region).toBe('OW');
        });
    });

    describe('parseTradeExecution', () => {
        const testCases: Array<{
            name: string;
            input: string;
            expected: Partial<TradeExecutionLogEntry>;
        }> = [
            {
                name: 'trade start',
                input: '2025-12-09T22:11:47Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 start',
                expected: {
                    type: 'trade_execution',
                    stage: 'start',
                    ship: {id: 8589938023, name: 'Q1'},
                    amount: 150,
                },
            },
            {
                name: 'before stage with stock levels',
                input: '2025-12-09T22:11:47Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 before: source = 494, destination = 441',
                expected: {
                    type: 'trade_execution',
                    stage: 'before',
                    data: {
                        sourceStock: 494,
                        destinationStock: 441,
                    },
                },
            },
            {
                name: 'moving to source',
                input: '2025-12-09T22:11:47Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Moving ship 8589938023 to source area 9602 (x=960, y=1682)',
                expected: {
                    type: 'trade_execution',
                    stage: 'moving_to_source',
                    data: {
                        x: 960,
                        y: 1682,
                    },
                },
            },
            {
                name: 'arrived at source',
                input: '2025-12-09T22:12:18Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Ship 8589938023 arrived at source area',
                expected: {
                    type: 'trade_execution',
                    stage: 'arrived_source',
                },
            },
            {
                name: 'loaded goods',
                input: '2025-12-09T22:12:22Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Loaded 150 total units; area src: 494 -> 344; moving to dst area (x=523 y=1578)',
                expected: {
                    type: 'trade_execution',
                    stage: 'loaded',
                    data: {
                        unloaded: 150,
                        srcBefore: 494,
                        srcAfter: 344,
                        x: 523,
                        y: 1578,
                    },
                },
            },
            {
                name: 'arrived at destination',
                input: '2025-12-09T22:13:10Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Ship arrived at destination area',
                expected: {
                    type: 'trade_execution',
                    stage: 'arrived_destination',
                },
            },
            {
                name: 'trade completed',
                input: '2025-12-09T22:13:14Z type=hub aDst="8706 (c1 (h))" ship="8589938023 (Q1)" iteration=1765311106 good="120008 (Wood)" region=OW loc=TradeExecutor._ExecuteTradeOrderWithShip aSrc="9602 (c2)" amount=150 Trade order completed: unloaded=150; src=(494 -> 344); dst=(441 -> 591)',
                expected: {
                    type: 'trade_execution',
                    stage: 'completed',
                    data: {
                        unloaded: 150,
                        srcBefore: 494,
                        srcAfter: 344,
                        dstBefore: 441,
                        dstAfter: 591,
                    },
                },
            },
        ];

        testCases.forEach(({name, input, expected}) => {
            it(name, () => {
                const result = parseLogLine(input);
                expect(result.type).toBe('trade_execution');
                Object.entries(expected).forEach(([key, value]) => {
                    if (typeof value === 'object' && value !== null) {
                        expect(result).toHaveProperty(key);
                        Object.entries(value).forEach(([subKey, subValue]) => {
                            expect((result as any)[key]).toHaveProperty(subKey, subValue);
                        });
                    } else {
                        expect(result).toHaveProperty(key, value);
                    }
                });
            });
        });
    });

    describe('parseIterationStart', () => {
        it('should parse iteration start', () => {
            const input =
                '2025-12-09T22:06:21Z region=OW loc=Trade.Loop type=regular iteration=1765310781 start at 2025-12-09 22:06:21 time';
            const result = parseLogLine(input) as IterationStartLogEntry;
            expect(result.type).toBe('iteration_start');
            expect(result.tradeType).toBe('regular');
            expect(result.iteration).toBe(1765310781);
        });
    });

    describe('generic fallback', () => {
        it('should return generic for unparsed lines', () => {
            const input =
                '2025-12-09T22:06:20Z loc=theTradeRouteAutomation_threads trade route automation main thread is running';
            const result = parseLogLine(input);
            expect(result.type).toBe('generic');
            expect(result.raw).toBe(input);
            expect(result.loc).toBe('theTradeRouteAutomation_threads');
        });

        it('should preserve timestamp on generic entries', () => {
            const input = '2025-12-09T22:06:20Z region=OW loc=Trade.Loop nil / 8514 (owner=nil) grid{ minX=1510 minY=1320 maxX=1780 maxY=1620 }';
            const result = parseLogLine(input);
            expect(result.type).toBe('generic');
            expect(result.timestamp).toBeDefined();
            expect(result.region).toBe('OW');
        });
    });
});
