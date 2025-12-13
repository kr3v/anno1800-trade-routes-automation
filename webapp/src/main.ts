/**
 * Trade Routes Analyzer - Main Entry Point
 */

import {
  isFileSystemAccessSupported,
  pickDirectory,
  saveDirectoryHandle,
  loadDirectoryHandle,
  type FileSystemDirectoryHandle,
} from './file-access';
import {
  TradeTableWidget,
  DeficitSurplusWidget,
  ShipUsageChartWidget,
  AreaVisualizerWidget,
  LogsTableWidget,
  StockTableWidget,
} from './widgets';
import {
  readStateFromURL,
  writeStateToURL,
  onURLStateChange,
  type AppState,
} from './url-state';
import { DataStore } from './data-store';

// App state
let dirHandle: FileSystemDirectoryHandle | null = null;
let dataStore: DataStore | null = null;
let currentDuration: string | null = null;
let currentRegion: string = 'OW';
let currentProfileName: string | null = null;

// Widgets
const tradeTableWidget = new TradeTableWidget();
const deficitSurplusWidget = new DeficitSurplusWidget();
const shipUsageWidget = new ShipUsageChartWidget();
const areaVisualizerWidget = new AreaVisualizerWidget();
const logsTableWidget = new LogsTableWidget();
const stockTableWidget = new StockTableWidget();

// DOM elements (will be initialized in init)
let pickFolderBtn: HTMLButtonElement;
let folderPathSpan: HTMLSpanElement;
let profileFilter: HTMLSelectElement;
let durationFilter: HTMLSelectElement;
let regionFilter: HTMLSelectElement;
let tabButtons: NodeListOf<HTMLButtonElement>;
let tabContents: NodeListOf<HTMLDivElement>;

/**
 * Initialize the application
 */
function init(): void {
  // Get DOM elements
  pickFolderBtn = document.getElementById('pick-folder') as HTMLButtonElement;
  folderPathSpan = document.getElementById('folder-path') as HTMLSpanElement;
  profileFilter = document.getElementById('profile-filter') as HTMLSelectElement;
  durationFilter = document.getElementById('duration-filter') as HTMLSelectElement;
  regionFilter = document.getElementById('region-filter') as HTMLSelectElement;
  tabButtons = document.querySelectorAll<HTMLButtonElement>('.tab');
  tabContents = document.querySelectorAll<HTMLDivElement>('.tab-content');

  // Check browser support
  // Read initial state from URL
  const urlState = readStateFromURL();
  currentDuration = urlState.duration;
  currentRegion = urlState.region;
  currentProfileName = urlState.profileName;

  // Apply URL state to UI
  if (durationFilter.querySelector(`option[value="${urlState.duration || ''}"]`)) {
    durationFilter.value = urlState.duration || '';
  }
  if (regionFilter.querySelector(`option[value="${urlState.region}"]`)) {
    regionFilter.value = urlState.region;
  }

  if (!isFileSystemAccessSupported()) {
    showError('File System Access API is not supported. Please use Chrome or Edge.');
    pickFolderBtn.disabled = true;
    return;
  }

  // Set up event listeners
  pickFolderBtn.addEventListener('click', handlePickFolder);

  profileFilter.addEventListener('change', () => {
    currentProfileName = profileFilter.value || null;
    writeStateToURL({ profileName: currentProfileName });
    if (dataStore) {
      loadTradesTab();
      loadLogsTab();
      loadStockTab();
    }
  });

  durationFilter.addEventListener('change', () => {
    currentDuration = durationFilter.value || null;
    tradeTableWidget.configure({ duration: currentDuration });
    writeStateToURL({ duration: currentDuration });
    if (dataStore) loadTradesTab();
  });

  // Configure trade table with navigation callback
  tradeTableWidget.configure({
    onNavigateToLogs: (filters) => {
      // Build URL state update
      const stateUpdate: Partial<AppState> = {
        tab: 'logs',
      };

      // If good is specified, set it as the only selected good
      if (filters.good) {
        stateUpdate.logGood = filters.good;
      }

      // If city is specified, set it as the only selected city for both src and dst
      if (filters.city) {
        stateUpdate.logAreaSrc = filters.city;
        stateUpdate.logAreaDst = filters.city;
      }

      // Update URL state (creates single history entry with tab + filters)
      writeStateToURL(stateUpdate);

      // Update tab UI without touching URL state (already updated above)
      updateTabUI('logs');

      // Apply the new filters to the logs table
      logsTableWidget.applyFiltersFromURL();
    }
  });

  regionFilter.addEventListener('change', () => {
    currentRegion = regionFilter.value;
    shipUsageWidget.configure({ region: currentRegion });
    writeStateToURL({ region: currentRegion });
    if (dataStore) loadTradesTab();
  });

  // Listen for browser back/forward
  onURLStateChange(handleURLStateChange);


  tabButtons.forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.dataset.tab!));
  });

  // Mount widgets to their containers
  const tradesContent = document.getElementById('trades-content')!;
  const shipUsageContainer = document.getElementById('tab-ship-usage')!;
  const areaContent = document.getElementById('area-content')!;
  const logsContent = document.getElementById('logs-content')!;
  const stockContent = document.getElementById('stock-content')!;

  // Create sub-containers for trades tab
  const tradeTableContainer = document.createElement('div');
  const deficitSurplusContainer = document.createElement('div');
  tradesContent.innerHTML = '';
  tradesContent.appendChild(tradeTableContainer);
  tradesContent.appendChild(deficitSurplusContainer);

  tradeTableWidget.mount(tradeTableContainer);
  deficitSurplusWidget.mount(deficitSurplusContainer);

  // Ship usage tab
  const shipUsageContent = document.createElement('div');
  shipUsageContent.id = 'ship-usage-content';
  shipUsageContainer.innerHTML = '';
  shipUsageContainer.appendChild(shipUsageContent);
  shipUsageWidget.mount(shipUsageContent);

  // Area visualizer
  areaVisualizerWidget.mount(areaContent);

  // Logs table
  logsTableWidget.mount(logsContent);

  // Stock table
  stockTableWidget.mount(stockContent);

  // Show initial state
  updateFolderPath();

  // Switch to tab from URL (no need to update URL, just UI)
  updateTabUI(urlState.tab);

  // Try to auto-load last used directory
  tryAutoLoadDirectory();
}

/**
 * Handle folder picker
 */
async function handlePickFolder(): Promise<void> {
  try {
    dirHandle = await pickDirectory();

    // Save to IndexedDB for auto-restore on next page load
    await saveDirectoryHandle(dirHandle);

    updateFolderPath();

    // Create DataStore and load all data upfront
    dataStore = new DataStore(dirHandle);
    await dataStore.load();

    await loadAllTabs();
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      // User cancelled - ignore
      return;
    }
    console.error('Failed to pick folder:', error);
    showError('Failed to pick folder');
  }
}

/**
 * Try to auto-load the last used directory from IndexedDB
 */
async function tryAutoLoadDirectory(): Promise<void> {
  try {
    const handle = await loadDirectoryHandle();

    if (handle) {
      console.log('Auto-loaded directory:', handle.name);
      dirHandle = handle;
      updateFolderPath();

      // Create DataStore and load all data upfront
      dataStore = new DataStore(dirHandle);
      await dataStore.load();

      await loadAllTabs();
    }
  } catch (error) {
    console.warn('Failed to auto-load directory:', error);
    // Silently fail - user can manually select folder
  }
}

/**
 * Update tab UI without touching URL state
 * Use this when URL state has already been updated separately
 */
function updateTabUI(tab: string): void {
  // Update tab button states
  tabButtons.forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tab);
  });

  // Update tab content visibility
  tabContents.forEach(content => {
    content.classList.toggle('active', content.id === `tab-${tab}`);
  });
}

/**
 * Switch to a different tab
 * Updates both UI and URL state
 */
function switchTab(tab: string): void {
  updateTabUI(tab);
  writeStateToURL({ tab });
}

/**
 * Populate profile name selector
 */
async function populateProfileSelector(): Promise<void> {
  if (!dataStore) return;

  try {
    const profileNames = dataStore.getProfileNames();

    profileFilter.innerHTML = '';

    if (profileNames.length === 0) {
      profileFilter.innerHTML = '<option value="">No profiles found</option>';
      profileFilter.disabled = true;
      currentProfileName = null;
      return;
    }

    profileFilter.disabled = false;

    // Add options
    profileNames.forEach(name => {
      const option = document.createElement('option');
      option.value = name;
      option.textContent = name;
      profileFilter.appendChild(option);
    });

    // Try to restore saved profile from URL or auto-select first
    if (currentProfileName && profileNames.includes(currentProfileName)) {
      profileFilter.value = currentProfileName;
    } else {
      currentProfileName = profileNames[0];
      profileFilter.value = currentProfileName;
      writeStateToURL({ profileName: currentProfileName });
    }
  } catch (error) {
    console.error('Failed to load profile names:', error);
    profileFilter.innerHTML = '<option value="">Error loading profiles</option>';
    profileFilter.disabled = true;
  }
}

/**
 * Load all tabs with data from directory
 */
async function loadAllTabs(): Promise<void> {
  if (!dataStore) return;

  // Populate profile selector first
  await populateProfileSelector();

  // Load all tabs in parallel
  await Promise.all([
    loadTradesTab(),
    loadLogsTab(),
    loadStockTab(),
    shipUsageWidget.load(dataStore),
    areaVisualizerWidget.load(dataStore),
  ]);
}

/**
 * Load trades tab data
 */
async function loadTradesTab(): Promise<void> {
  if (!dataStore || !currentProfileName) return;

  await Promise.all([
    tradeTableWidget.load(dataStore, currentProfileName),
    deficitSurplusWidget.load(dataStore, currentProfileName, currentRegion),
  ]);
}

/**
 * Load logs tab data
 */
async function loadLogsTab(): Promise<void> {
  if (!dataStore || !currentProfileName) return;

  await logsTableWidget.load(dataStore, currentProfileName);
}

/**
 * Load stock tab data
 */
async function loadStockTab(): Promise<void> {
  if (!dataStore || !currentProfileName) return;

  await stockTableWidget.load(dataStore, currentProfileName);
}

/**
 * Handle URL state changes from browser back/forward
 */
function handleURLStateChange(state: AppState): void {
  // Update filters
  if (state.profileName !== currentProfileName) {
    currentProfileName = state.profileName;
    if (profileFilter && state.profileName) {
      profileFilter.value = state.profileName;
    }
    if (dataStore) {
      loadTradesTab();
      loadLogsTab();
      loadStockTab();
    }
  }

  if (state.duration !== currentDuration) {
    currentDuration = state.duration;
    durationFilter.value = state.duration || '';
    tradeTableWidget.configure({ duration: currentDuration });
    if (dataStore) loadTradesTab();
  }

  if (state.region !== currentRegion) {
    currentRegion = state.region;
    regionFilter.value = state.region;
    shipUsageWidget.configure({ region: currentRegion });
    if (dataStore) loadTradesTab();
  }

  // Update area visualizer state
  areaVisualizerWidget.restoreState(state);

  // Update tab UI to match URL (URL already changed via back/forward)
  updateTabUI(state.tab);
}


/**
 * Update folder path display
 */
function updateFolderPath(): void {
  if (dirHandle) {
    folderPathSpan.textContent = dirHandle.name;
    folderPathSpan.title = dirHandle.name;
  } else {
    folderPathSpan.textContent = 'No folder selected';
    folderPathSpan.title = '';
  }
}

/**
 * Show error message
 */
function showError(message: string): void {
  // Simple alert for now - could be improved with toast notifications
  alert(message);
}

// Initialize on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
