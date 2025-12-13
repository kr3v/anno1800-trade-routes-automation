/**
 * URL State Management
 * Syncs application state to URL query parameters for bookmarking and sharing
 */

export interface AppState {
  // Active tab
  tab: string;

  // Trades tab filters
  duration: string | null;
  region: string;
  profileName: string | null;

  // Area visualizer filters
  game: string | null;
  areaRegion: string | null;
  city: string | null;

  // Logs tab filters
  logType: string | null;
  logRegion: string | null;
  logIteration: string | null;
  logIterationType: string | null;
  logAreaSrc: string | null;
  logAreaDst: string | null;
  logAreaMode: string | null;
  logShip: string | null;
  logGood: string | null;
  logOtherDataRegex: string | null;

  // Stock tab filters
  stockRegion: string | null;
  stockCity: string | null;
  stockGood: string | null;
  stockLegend: string | null;
  stockCategory: string | null;
  stockReason: string | null;
  stockOnlyLatest: string | null;
  stockSortBy: string | null;
  stockSortByCity: string | null;
  stockSortOrder: string | null;
}

const DEFAULT_STATE: AppState = {
  tab: 'trades',
  duration: null,
  region: 'OW',
  profileName: null,
  game: null,
  areaRegion: null,
  city: null,
  logType: null,
  logRegion: null,
  logIteration: null,
  logIterationType: null,
  logAreaSrc: null,
  logAreaDst: null,
  logAreaMode: null,
  logShip: null,
  logGood: null,
  logOtherDataRegex: null,
  stockRegion: null,
  stockCity: null,
  stockGood: null,
  stockLegend: null,
  stockCategory: null,
  stockReason: null,
  stockOnlyLatest: null,
  stockSortBy: null,
  stockSortByCity: null,
  stockSortOrder: null,
};

/**
 * Encode a filter set for URL with smart compression:
 * - If all options are selected, return "ALL"
 * - If only one item is deselected, return "ALL\item"
 * - If less than half are selected, return comma-separated list
 * - If more than half are selected, return "ALL\excluded1,excluded2"
 *
 * @param selected Set of selected items
 * @param allOptions Set of all available options
 * @returns Encoded string or null if empty
 */
export function encodeFilterSet(selected: Set<string>, allOptions: Set<string>): string | null {
  if (selected.size === 0) {
    return null; // No items selected
  }

  if (selected.size === allOptions.size) {
    return 'ALL'; // All items selected
  }

  const selectedArray = Array.from(selected).sort();
  const allArray = Array.from(allOptions).sort();

  // Calculate excluded items
  const excluded = allArray.filter(item => !selected.has(item));

  // If only one item excluded, use exclusion syntax
  if (excluded.length === 1) {
    return `ALL\\${excluded[0]}`;
  }

  // If more than half selected, use exclusion list
  if (selected.size > allOptions.size / 2) {
    return `ALL\\${excluded.join(',')}`;
  }

  // Otherwise, use inclusion list
  return selectedArray.join(',');
}

/**
 * Decode a filter set from URL string
 *
 * @param encoded Encoded string from URL
 * @param allOptions Set of all available options
 * @returns Decoded Set of selected items, or null if ALL or empty
 */
export function decodeFilterSet(encoded: string | null, allOptions: Set<string>): Set<string> | null {
  if (!encoded) {
    return null; // Empty filter means show all
  }

  if (encoded === 'ALL') {
    return new Set(allOptions); // All selected
  }

  // Check for exclusion syntax: ALL\item1,item2
  if (encoded.startsWith('ALL\\')) {
    const excludedStr = encoded.slice(4); // Remove "ALL\"
    const excluded = new Set(excludedStr.split(','));
    const result = new Set<string>();
    for (const item of allOptions) {
      if (!excluded.has(item)) {
        result.add(item);
      }
    }
    return result;
  }

  // Regular comma-separated list
  const items = encoded.split(',');
  return new Set(items.filter(item => allOptions.has(item))); // Only include valid items
}

/**
 * Read application state from URL query parameters
 */
export function readStateFromURL(): AppState {
  const params = new URLSearchParams(window.location.search);

  return {
    tab: params.get('tab') || DEFAULT_STATE.tab,
    duration: params.get('duration') || DEFAULT_STATE.duration,
    region: params.get('region') || DEFAULT_STATE.region,
    profileName: params.get('profileName'),
    game: params.get('game'),
    areaRegion: params.get('areaRegion'),
    city: params.get('city'),
    logType: params.get('logType'),
    logRegion: params.get('logRegion'),
    logIteration: params.get('logIteration'),
    logIterationType: params.get('logIterationType'),
    logAreaSrc: params.get('logAreaSrc'),
    logAreaDst: params.get('logAreaDst'),
    logAreaMode: params.get('logAreaMode'),
    logShip: params.get('logShip'),
    logGood: params.get('logGood'),
    logOtherDataRegex: params.get('logOtherDataRegex'),
    stockRegion: params.get('stockRegion'),
    stockCity: params.get('stockCity'),
    stockGood: params.get('stockGood'),
    stockLegend: params.get('stockLegend'),
    stockCategory: params.get('stockCategory'),
    stockReason: params.get('stockReason'),
    stockOnlyLatest: params.get('stockOnlyLatest'),
    stockSortBy: params.get('stockSortBy'),
    stockSortByCity: params.get('stockSortByCity'),
    stockSortOrder: params.get('stockSortOrder'),
  };
}

/**
 * Write application state to URL query parameters
 * Uses pushState for tab changes (adds to browser history)
 * Uses replaceState for filter changes (avoids polluting browser history)
 */
export function writeStateToURL(state: Partial<AppState>): void {
  const currentState = readStateFromURL();
  const newState = { ...currentState, ...state };

  const params = new URLSearchParams();

  // Only add non-default values to keep URL clean
  if (newState.tab !== DEFAULT_STATE.tab) {
    params.set('tab', newState.tab);
  }

  if (newState.duration) {
    params.set('duration', newState.duration);
  }

  if (newState.region !== DEFAULT_STATE.region) {
    params.set('region', newState.region);
  }

  if (newState.profileName) {
    params.set('profileName', newState.profileName);
  }

  if (newState.game) {
    params.set('game', newState.game);
  }

  if (newState.areaRegion) {
    params.set('areaRegion', newState.areaRegion);
  }

  if (newState.city) {
    params.set('city', newState.city);
  }

  // Log filters
  if (newState.logType) {
    params.set('logType', newState.logType);
  }

  if (newState.logRegion) {
    params.set('logRegion', newState.logRegion);
  }

  if (newState.logIteration) {
    params.set('logIteration', newState.logIteration);
  }

  if (newState.logIterationType) {
    params.set('logIterationType', newState.logIterationType);
  }

  if (newState.logAreaSrc) {
    params.set('logAreaSrc', newState.logAreaSrc);
  }

  if (newState.logAreaDst) {
    params.set('logAreaDst', newState.logAreaDst);
  }

  if (newState.logAreaMode) {
    params.set('logAreaMode', newState.logAreaMode);
  }

  if (newState.logShip) {
    params.set('logShip', newState.logShip);
  }

  if (newState.logGood) {
    params.set('logGood', newState.logGood);
  }

  if (newState.logOtherDataRegex) {
    params.set('logOtherDataRegex', newState.logOtherDataRegex);
  }

  // Stock filters
  if (newState.stockRegion) {
    params.set('stockRegion', newState.stockRegion);
  }

  if (newState.stockCity) {
    params.set('stockCity', newState.stockCity);
  }

  if (newState.stockGood) {
    params.set('stockGood', newState.stockGood);
  }

  if (newState.stockLegend) {
    params.set('stockLegend', newState.stockLegend);
  }

  if (newState.stockCategory) {
    params.set('stockCategory', newState.stockCategory);
  }

  if (newState.stockReason) {
    params.set('stockReason', newState.stockReason);
  }

  if (newState.stockOnlyLatest) {
    params.set('stockOnlyLatest', newState.stockOnlyLatest);
  }

  if (newState.stockSortBy) {
    params.set('stockSortBy', newState.stockSortBy);
  }

  if (newState.stockSortByCity) {
    params.set('stockSortByCity', newState.stockSortByCity);
  }

  if (newState.stockSortOrder) {
    params.set('stockSortOrder', newState.stockSortOrder);
  }

  // Build new URL
  const newURL = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;

  // Detect if this is a tab change
  const isTabChange = 'tab' in state && state.tab !== currentState.tab;

  // Use pushState for tab changes (adds to browser history)
  // Use replaceState for filter changes (doesn't pollute history)
  if (isTabChange) {
    window.history.pushState(null, '', newURL);
  } else {
    window.history.replaceState(null, '', newURL);
  }
}

/**
 * Clear all state from URL
 */
export function clearURLState(): void {
  window.history.replaceState(null, '', window.location.pathname);
}

/**
 * Listen for popstate events (browser back/forward)
 */
export function onURLStateChange(callback: (state: AppState) => void): () => void {
  const handler = () => {
    callback(readStateFromURL());
  };
  
  window.addEventListener('popstate', handler);
  
  // Return cleanup function
  return () => {
    window.removeEventListener('popstate', handler);
  };
}

