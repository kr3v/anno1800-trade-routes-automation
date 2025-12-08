/**
 * Parser for trade-executor-history.json
 */

import type { FileSystemDirectoryHandle } from '@/file-access';
import { readJsonFromDirectory, readJsonFromDirectoryResult, type Result, Ok } from '@/file-access';
import type { GoodsNameMap } from './texts';
import { resolveGoodName } from './texts';

/** Raw trade entry from JSON */
export interface RawTradeEntry {
  good_id: number;
  good_name?: string;
  good_amount: number;
  area_src_name: string;
  area_dst_name: string;
  _start: string;
  _end: string;
}

/** Parsed trade entry */
export interface TradeEntry {
  goodId: string;
  goodName: string;
  amount: number;
  sourceName: string;
  destName: string;
  startTime: Date;
  endTime: Date;
}

/** Aggregated trade data per city/good */
export interface CityGoodData {
  amount: number;
  firstTime: Date | null;
  lastTime: Date | null;
}

/** Trade analysis result */
export interface TradeAnalysis {
  /** Goods received per city: city -> good -> data */
  received: Map<string, Map<string, CityGoodData>>;
  /** Goods sent per city: city -> good -> data */
  sent: Map<string, Map<string, CityGoodData>>;
  /** All unique city names */
  cities: Set<string>;
  /** All unique good names */
  goods: Set<string>;
  /** Maximum single trade amount (for color scaling) */
  maxAmount: number;
  /** Total number of trades */
  tradeCount: number;
  /** Time range */
  timeRange: { start: Date | null; end: Date | null };
}

/**
 * Parse ISO timestamp string to Date
 * Note: 'Z' in logs represents local timezone, not UTC
 */
export function parseTimestamp(tsStr: string): Date {
  // Remove 'Z' and parse as local time
  if (tsStr.endsWith('Z')) {
    return new Date(tsStr.slice(0, -1));
  }
  return new Date(tsStr);
}

/**
 * Parse duration string like '15m', '2h', '1d' into milliseconds
 */
export function parseDuration(durationStr: string): number | null {
  const match = durationStr.toLowerCase().match(/^(\d+)([mhd])$/);
  if (!match) return null;

  const value = parseInt(match[1], 10);
  const unit = match[2];

  switch (unit) {
    case 'm': return value * 60 * 1000;
    case 'h': return value * 60 * 60 * 1000;
    case 'd': return value * 24 * 60 * 60 * 1000;
    default: return null;
  }
}

/**
 * Load and parse trades from trade-executor-history.json
 */
export async function loadTrades(
  dirHandle: FileSystemDirectoryHandle,
  path: string,
  goodsNames: GoodsNameMap = {}
): Promise<TradeEntry[]> {
  const raw = await readJsonFromDirectory<RawTradeEntry[]>(dirHandle, path);
  if (!raw) return [];

  return raw.map(entry => ({
    goodId: String(entry.good_id),
    goodName: entry.good_name ?? resolveGoodName(entry.good_id, goodsNames),
    amount: entry.good_amount,
    sourceName: entry.area_src_name,
    destName: entry.area_dst_name,
    startTime: parseTimestamp(entry._start),
    endTime: parseTimestamp(entry._end),
  }));
}

/**
 * Load and parse trades from trade-executor-history.json (Result version)
 */
export async function loadTradesResult(
  dirHandle: FileSystemDirectoryHandle,
  path: string,
  goodsNames: GoodsNameMap = {}
): Promise<Result<TradeEntry[]>> {
  const result = await readJsonFromDirectoryResult<RawTradeEntry[]>(dirHandle, path);

  if (!result.ok) {
    return result;
  }

  const trades = result.value.map(entry => ({
    goodId: String(entry.good_id),
    goodName: entry.good_name ?? resolveGoodName(entry.good_id, goodsNames),
    amount: entry.good_amount,
    sourceName: entry.area_src_name,
    destName: entry.area_dst_name,
    startTime: parseTimestamp(entry._start),
    endTime: parseTimestamp(entry._end),
  }));

  return Ok(trades);
}

/**
 * Filter trades by time duration
 */
export function filterTradesByDuration(
  trades: TradeEntry[],
  duration: string | null
): TradeEntry[] {
  if (!duration) return trades;

  const durationMs = parseDuration(duration);
  if (!durationMs) return trades;

  const cutoff = new Date(Date.now() - durationMs);
  return trades.filter(t => t.startTime >= cutoff);
}

/**
 * Analyze trades and aggregate by city/good
 */
export function analyzeTrades(trades: TradeEntry[]): TradeAnalysis {
  const received = new Map<string, Map<string, CityGoodData>>();
  const sent = new Map<string, Map<string, CityGoodData>>();
  const cities = new Set<string>();
  const goods = new Set<string>();
  let maxAmount = 0;
  let startTime: Date | null = null;
  let endTime: Date | null = null;

  for (const trade of trades) {
    cities.add(trade.sourceName);
    cities.add(trade.destName);
    goods.add(trade.goodName);
    maxAmount = Math.max(maxAmount, trade.amount);

    if (!startTime || trade.startTime < startTime) startTime = trade.startTime;
    if (!endTime || trade.endTime > endTime) endTime = trade.endTime;

    // Update received (destination city)
    if (!received.has(trade.destName)) {
      received.set(trade.destName, new Map());
    }
    const destGoods = received.get(trade.destName)!;
    if (!destGoods.has(trade.goodName)) {
      destGoods.set(trade.goodName, { amount: 0, firstTime: null, lastTime: null });
    }
    const destData = destGoods.get(trade.goodName)!;
    destData.amount += trade.amount;
    if (!destData.firstTime || trade.startTime < destData.firstTime) {
      destData.firstTime = trade.startTime;
    }
    if (!destData.lastTime || trade.endTime > destData.lastTime) {
      destData.lastTime = trade.endTime;
    }

    // Update sent (source city)
    if (!sent.has(trade.sourceName)) {
      sent.set(trade.sourceName, new Map());
    }
    const srcGoods = sent.get(trade.sourceName)!;
    if (!srcGoods.has(trade.goodName)) {
      srcGoods.set(trade.goodName, { amount: 0, firstTime: null, lastTime: null });
    }
    const srcData = srcGoods.get(trade.goodName)!;
    srcData.amount += trade.amount;
    if (!srcData.firstTime || trade.startTime < srcData.firstTime) {
      srcData.firstTime = trade.startTime;
    }
    if (!srcData.lastTime || trade.endTime > srcData.lastTime) {
      srcData.lastTime = trade.endTime;
    }
  }

  return {
    received,
    sent,
    cities,
    goods,
    maxAmount,
    tradeCount: trades.length,
    timeRange: { start: startTime, end: endTime },
  };
}

/**
 * Sort cities by type (c* first, then n*) and by total volume
 */
export function sortCities(cities: Set<string>, analysis: TradeAnalysis): string[] {
  const cityVolumes = new Map<string, number>();

  for (const city of cities) {
    let volume = 0;
    const recvGoods = analysis.received.get(city);
    const sentGoods = analysis.sent.get(city);

    if (recvGoods) {
      for (const data of recvGoods.values()) {
        volume += data.amount;
      }
    }
    if (sentGoods) {
      for (const data of sentGoods.values()) {
        volume += data.amount;
      }
    }
    cityVolumes.set(city, volume);
  }

  const cCities = [...cities].filter(c => c.startsWith('c'));
  const nCities = [...cities].filter(c => c.startsWith('n'));
  const otherCities = [...cities].filter(c => !c.startsWith('c') && !c.startsWith('n'));

  const sortByVolume = (a: string, b: string) =>
    (cityVolumes.get(b) ?? 0) - (cityVolumes.get(a) ?? 0);

  return [
    ...cCities.sort(sortByVolume),
    ...nCities.sort(sortByVolume),
    ...otherCities.sort(sortByVolume),
  ];
}

/**
 * Sort goods by total volume
 */
export function sortGoods(goods: Set<string>, analysis: TradeAnalysis): string[] {
  const goodVolumes = new Map<string, number>();

  for (const good of goods) {
    let volume = 0;
    for (const cityGoods of analysis.received.values()) {
      volume += cityGoods.get(good)?.amount ?? 0;
    }
    for (const cityGoods of analysis.sent.values()) {
      volume += cityGoods.get(good)?.amount ?? 0;
    }
    goodVolumes.set(good, volume);
  }

  return [...goods].sort((a, b) => (goodVolumes.get(b) ?? 0) - (goodVolumes.get(a) ?? 0));
}
