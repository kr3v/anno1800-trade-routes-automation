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
}

const DEFAULT_STATE: AppState = {
  tab: 'trades',
  duration: null,
  region: 'OW',
  profileName: null,
  game: null,
  areaRegion: null,
  city: null,
};

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
  };
}

/**
 * Write application state to URL query parameters
 * Uses replaceState to avoid polluting browser history
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
  
  // Update URL without reloading page or adding to history
  const newURL = params.toString() 
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  
  window.history.replaceState(null, '', newURL);
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

