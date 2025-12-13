/**
 * Stock Table Widget
 * Displays latest stock information for all cities/areas in a table format
 * Rows: Goods, Columns: Cities, Cells: Stock/Request info with color coding
 */

import type { DataStore } from '@/data-store';
import type { LogEntry, AreaStockLogEntry } from '@/parsers/base-log';
import { encodeFilterSet, decodeFilterSet, writeStateToURL, readStateFromURL } from '@/url-state';

export interface StockTableConfig {
  // Filter values
  regionFilter: Set<string>; // Regions (OW, NW, AR, EN, CT)
  cityFilter: Set<string>; // City/area names
  goodFilter: Set<string>; // Good names
  legendFilter: Set<string>; // Legend types (bold-green, green, neutral, red, bold-red)
  categoryFilter: Set<string>; // Main categories (Population, Production, Construction, etc.)
  reasonFilter: Set<string>; // Exact reasons (Population/Worker Residence, etc.)
  onlyLatestIteration: boolean; // Only show stock from latest iteration per region
  sortBy: 'stock' | 'request'; // Primary sort field (stock or request)
  sortByCity: string | null; // City to sort by (null = no city-based sorting)
  sortOrder: 'asc' | 'desc' | null; // Sort order (null = not sorting by city)
}

/**
 * Stock data for a specific area/good combination
 */
interface StockData {
  stock: number;
  request: number;
  inFlightIn: number;
  inFlightOut: number;
  iteration: number;
  timestamp: Date;
  region: string;
  reasons?: string[];
}

/**
 * Aggregated stock data by good and area
 */
interface AggregatedStockData {
  // Map: goodName -> areaName -> StockData
  stocks: Map<string, Map<string, StockData>>;
  // Latest iteration per region
  latestIterations: Map<string, number>;
  // All unique good names
  goodNames: Set<string>;
  // All unique area names
  areaNames: Set<string>;
  // All unique regions
  regions: Set<string>;
  // All unique categories (main category from reasons like "Population", "Production")
  categories: Set<string>;
  // All unique exact reasons
  exactReasons: Set<string>;
}

/**
 * Clean up name by replacing underscores with spaces
 */
function cleanName(name: string): string {
  return name.replace(/_/g, ' ');
}

/**
 * Format iteration timestamp (YYYYMMDDHHmmss) as human-readable date
 */
function formatIterationTimestamp(iteration: number, trimToday: boolean = false): string {
  const iterStr = iteration.toString();

  // Check if it looks like a timestamp (14 digits: YYYYMMDDHHmmss)
  if (iterStr.length !== 14) {
    return iteration.toString(); // Return as-is if not a timestamp
  }

  try {
    const year = iterStr.substring(0, 4);
    const month = iterStr.substring(4, 6);
    const day = iterStr.substring(6, 8);
    const hour = iterStr.substring(8, 10);
    const minute = iterStr.substring(10, 12);
    const second = iterStr.substring(12, 14);

    const dateStr = `${year}-${month}-${day}`;
    const timeStr = `${hour}:${minute}:${second}`;

    // If trimToday is enabled, check if date matches today
    if (trimToday) {
      const today = new Date();
      const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
      if (dateStr === todayStr) {
        return timeStr; // Return only time if it's today
      }
    }

    return `${dateStr} ${timeStr}`;
  } catch {
    return iteration.toString(); // Fallback if parsing fails
  }
}

/**
 * Calculate time delta between two iteration timestamps
 */
function calculateIterationDelta(oldIteration: number, newIteration: number): string {
  const oldStr = oldIteration.toString();
  const newStr = newIteration.toString();

  if (oldStr.length !== 14 || newStr.length !== 14) {
    return ''; // Not valid timestamps
  }

  try {
    // Parse timestamps
    const parseTimestamp = (str: string): Date => {
      const year = parseInt(str.substring(0, 4));
      const month = parseInt(str.substring(4, 6)) - 1; // JS months are 0-indexed
      const day = parseInt(str.substring(6, 8));
      const hour = parseInt(str.substring(8, 10));
      const minute = parseInt(str.substring(10, 12));
      const second = parseInt(str.substring(12, 14));
      return new Date(year, month, day, hour, minute, second);
    };

    const oldDate = parseTimestamp(oldStr);
    const newDate = parseTimestamp(newStr);

    const deltaMs = newDate.getTime() - oldDate.getTime();
    const deltaSeconds = Math.floor(deltaMs / 1000);

    if (deltaSeconds < 60) {
      return `${deltaSeconds}s`;
    } else if (deltaSeconds < 3600) {
      const minutes = Math.floor(deltaSeconds / 60);
      return `${minutes}m`;
    } else if (deltaSeconds < 86400) {
      const hours = Math.floor(deltaSeconds / 3600);
      const minutes = Math.floor((deltaSeconds % 3600) / 60);
      return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
    } else {
      const days = Math.floor(deltaSeconds / 86400);
      const hours = Math.floor((deltaSeconds % 86400) / 3600);
      return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
    }
  } catch {
    return '';
  }
}

/**
 * Convert good name to icon filename
 */
function getGoodIconPath(goodName: string): string {
  const iconName = goodName.toLowerCase().replace(/\s+/g, '_');
  return `${import.meta.env.BASE_URL}icon_${iconName}.png`;
}

/**
 * Aggregate stock data from log entries
 */
function aggregateStockData(logs: LogEntry[]): AggregatedStockData {
  const stocks = new Map<string, Map<string, StockData>>();
  const latestIterations = new Map<string, number>();
  const goodNames = new Set<string>();
  const areaNames = new Set<string>();
  const regions = new Set<string>();
  const categories = new Set<string>();
  const exactReasons = new Set<string>();

  // Filter only area_stock entries
  const stockEntries = logs.filter((log): log is AreaStockLogEntry => log.type === 'area_stock');

  // Track latest iteration per region
  for (const entry of stockEntries) {
    if (entry.region) {
      const currentLatest = latestIterations.get(entry.region) ?? 0;
      if (entry.iteration > currentLatest) {
        latestIterations.set(entry.region, entry.iteration);
      }
    }
  }

  // Process each stock entry
  for (const entry of stockEntries) {
    const goodName = cleanName(entry.goodName);
    const areaName = cleanName(entry.areaName);
    const region = entry.region || 'Unknown';

    goodNames.add(goodName);
    areaNames.add(areaName);
    regions.add(region);

    // Extract categories and exact reasons from reasons
    if (entry.reasons) {
      for (const reason of entry.reasons) {
        exactReasons.add(reason);
        // Extract main category (before the first "/")
        const categoryMatch = reason.match(/^([^/]+)/);
        if (categoryMatch) {
          categories.add(categoryMatch[1]);
        }
      }
    }

    // Get or create good map
    if (!stocks.has(goodName)) {
      stocks.set(goodName, new Map());
    }
    const goodMap = stocks.get(goodName)!;

    // Check if this is the latest entry for this area+good combination
    const existing = goodMap.get(areaName);
    if (!existing || entry.iteration > existing.iteration) {
      goodMap.set(areaName, {
        stock: entry.stock,
        request: entry.request,
        inFlightIn: entry.inFlightIn,
        inFlightOut: entry.inFlightOut,
        iteration: entry.iteration,
        timestamp: entry.timestamp,
        region,
        reasons: entry.reasons,
      });
    }
  }

  return { stocks, latestIterations, goodNames, areaNames, regions, categories, exactReasons };
}

/**
 * Classify stock status based on stock/request values
 */
type StockClassification = 'bold-green' | 'green' | 'red' | 'unavailable';

function classifyStock(stock: number, request: number): StockClassification {
  if (stock === 0 && request > 0) {
    return 'unavailable'; // Completely unavailable
  } else if (stock >= request) {
    return stock >= request * 2 ? 'bold-green' : 'green';
  } else {
    return 'red';
  }
}

/**
 * Get CSS class for stock classification
 */
function getStockClass(classification: StockClassification): string {
  switch (classification) {
    case 'bold-green': return 'stock-high-bold';
    case 'green': return 'stock-high';
    case 'red': return 'stock-low';
    case 'unavailable': return 'stock-unavailable';
  }
}

/**
 * Build a tree structure from reasons
 */
function buildReasonTree(reasons: string[]): { category: string; details: string[] }[] {
  const tree = new Map<string, Set<string>>();

  for (const reason of reasons) {
    const parts = reason.split('/');
    if (parts.length === 1) {
      // No subcategory, just add as-is
      if (!tree.has(reason)) {
        tree.set(reason, new Set());
      }
    } else {
      // Has subcategory
      const category = parts[0];
      const detail = parts.slice(1).join('/');
      if (!tree.has(category)) {
        tree.set(category, new Set());
      }
      tree.get(category)!.add(detail);
    }
  }

  // Convert to array format
  return Array.from(tree.entries()).map(([category, details]) => ({
    category,
    details: Array.from(details).sort(),
  }));
}

/**
 * Get color class for a category
 */
function getCategoryColor(category: string): string {
  const lowerCategory = category.toLowerCase();
  if (lowerCategory.startsWith('po')) return 'reason-cat-population'; // Green
  if (lowerCategory.startsWith('pr')) return 'reason-cat-production'; // Purple
  if (lowerCategory.startsWith('c')) return 'reason-cat-construction'; // Blue
  return '';
}

/**
 * Abbreviate a reason string into short code with colored category
 * Examples:
 *   Construction -> <span class="reason-cat-construction">C</span>
 *   Production/Bakery -> <span class="reason-cat-production">Pr</span>/Bak
 *   Population/Worker Residence -> <span class="reason-cat-population">Po</span>/W
 */
function abbreviateReason(reason: string): string {
  const parts = reason.split('/');

  if (parts.length === 1) {
    // Single word - take first letter, capitalize
    const abbr = parts[0].charAt(0).toUpperCase();
    const colorClass = getCategoryColor(abbr);
    return colorClass ? `<span class="${colorClass}">${abbr}</span>` : abbr;
  }

  // Has category and subcategory
  const category = parts[0];
  let subcategory = parts[1];

  // Drop everything after colon
  if (subcategory.includes(':')) {
    subcategory = subcategory.split(':')[0].trim();
  }

  // Drop "Residence" if present
  subcategory = subcategory.replace(/\s*Residence\s*/g, '').trim();

  // Abbreviate category (first 2 letters or first letter of each word)
  const categoryAbbr = category.length <= 3
    ? category.charAt(0).toUpperCase()
    : category.substring(0, 2);

  // Abbreviate subcategory - take first letter of each word
  const subcategoryWords = subcategory.split(/\s+/);
  const subcategoryAbbr = subcategoryWords
    .map(word => word.charAt(0).toUpperCase())
    .join('');

  const colorClass = getCategoryColor(categoryAbbr);
  const coloredCategory = colorClass ? `<span class="${colorClass}">${categoryAbbr}</span>` : categoryAbbr;

  return `${coloredCategory}/${subcategoryAbbr}`;
}

/**
 * Get all unique reasons for a good across all areas
 */
function getGoodReasons(goodMap: Map<string, StockData>): string[] {
  const allReasons = new Set<string>();
  for (const data of goodMap.values()) {
    if (data.reasons) {
      data.reasons.forEach(r => allReasons.add(r));
    }
  }
  return Array.from(allReasons).sort();
}

/**
 * Format a stock cell with color coding and expandable reasons
 */
function formatStockCell(
  data: StockData | null | undefined,
  latestIteration: number | undefined,
  onlyLatest: boolean,
  cellKey: string,
  isExpanded: boolean
): string {
  if (!data) {
    return '<span class="stock-no-data">-</span>';
  }

  // Check if this is from an outdated iteration
  const isOutdated = latestIteration !== undefined && data.iteration < latestIteration;

  if (onlyLatest && isOutdated) {
    return '<span class="stock-no-data">-</span>';
  }

  const { stock, request, inFlightIn, inFlightOut } = data;

  // Determine stock color class
  const classification = classifyStock(stock, request);
  const stockClass = getStockClass(classification);

  // Determine request color class
  const requestClass = stock >= request ? 'request-ok' : 'request-alert';

  // Format in/out
  const inText = inFlightIn !== 0 ? `+${inFlightIn}` : '';
  const outText = inFlightOut !== 0 ? `-${Math.abs(inFlightOut)}` : '';
  const flightText = [inText, outText].filter(Boolean).join('/');

  // Build cell content
  const outdatedMarker = isOutdated && !onlyLatest ? '*' : '';
  let outdatedTitle = '';
  if (outdatedMarker && latestIteration !== undefined) {
    const oldIterStr = formatIterationTimestamp(data.iteration);
    const latestIterStr = formatIterationTimestamp(latestIteration);
    const delta = calculateIterationDelta(data.iteration, latestIteration);
    const deltaStr = delta ? `, ${delta} behind` : '';
    outdatedTitle = `title="Iteration ${oldIterStr} (latest: ${latestIterStr}${deltaStr})"`;
  }

  // Add expand/collapse indicator if there are reasons
  const hasReasons = data.reasons && data.reasons.length > 0;
  const expandIndicator = hasReasons ? (isExpanded ? ' \u25BC' : ' \u25B6') : ''; // ▼ or ▶
  const clickable = hasReasons ? `class="stock-cell-expandable" data-cell-key="${cellKey}"` : '';

  let reasonsHtml = '';
  if (hasReasons && isExpanded) {
    const tree = buildReasonTree(data.reasons!);
    const reasonsList = tree
      .map(({ category, details }) => {
        if (details.length === 0) {
          return `<div class="reason-item reason-category-only">${category}</div>`;
        } else {
          const detailsHtml = details
            .map((detail) => `<div class="reason-item reason-detail">${detail}</div>`)
            .join('');
          return `<div class="reason-item reason-category">${category}</div>${detailsHtml}`;
        }
      })
      .join('');
    reasonsHtml = `<div class="stock-reasons">${reasonsList}</div>`;
  }

  return `
    <div class="stock-cell" ${clickable}>
      <div class="stock-cell-main">
        <span class="${stockClass}">${stock}</span>/<span class="${requestClass}">${request}</span>${expandIndicator}
        ${flightText ? `<span class="stock-flight">(${flightText})</span>` : ''}
        ${outdatedMarker ? `<span class="stock-outdated" ${outdatedTitle}>${outdatedMarker}</span>` : ''}
      </div>
      ${reasonsHtml}
    </div>
  `;
}

export class StockTableWidget {
  private container: HTMLElement | null = null;
  private config: StockTableConfig = {
    regionFilter: new Set(),
    cityFilter: new Set(),
    goodFilter: new Set(),
    legendFilter: new Set(),
    categoryFilter: new Set(),
    reasonFilter: new Set(),
    onlyLatestIteration: true,
    sortBy: 'stock',
    sortByCity: null,
    sortOrder: null,
  };
  private aggregatedData: AggregatedStockData | null = null;
  private expandedCells: Set<string> = new Set(); // Track expanded cells by "goodName:areaName" key

  configure(config: Partial<StockTableConfig>): void {
    this.config = { ...this.config, ...config };
  }

  async mount(container: HTMLElement): Promise<void> {
    this.container = container;
    container.innerHTML = '<div class="tab-placeholder">Loading...</div>';
  }

  async load(dataStore: DataStore, profileName: string): Promise<void> {
    if (!this.container) return;

    // Get base logs from DataStore
    const logs = dataStore.getBaseLogs(profileName);

    if (!logs) {
      this.container.innerHTML = `<div class="error">No logs found for profile: ${profileName}</div>`;
      return;
    }

    if (logs.length === 0) {
      this.container.innerHTML = '<div class="error">No logs recorded</div>';
      return;
    }

    // Aggregate stock data
    this.aggregatedData = aggregateStockData(logs);

    if (this.aggregatedData.goodNames.size === 0) {
      this.container.innerHTML = '<div class="error">No stock data found in logs</div>';
      return;
    }

    // Try to restore filters from URL first
    const urlState = readStateFromURL();
    const restoredFromURL = this.restoreFiltersFromURL(urlState);

    if (!restoredFromURL) {
      // Initialize filters with defaults (all selected)
      this.config.regionFilter = new Set(this.aggregatedData.regions);
      this.config.cityFilter = new Set(this.aggregatedData.areaNames);
      this.config.goodFilter = new Set(this.aggregatedData.goodNames);
      this.config.legendFilter = new Set(); // Empty = show all
      this.config.categoryFilter = new Set(); // Empty = show all
      this.config.reasonFilter = new Set(); // Empty = show all
      this.config.onlyLatestIteration = true;
      this.config.sortBy = 'stock';
      this.config.sortByCity = null;
      this.config.sortOrder = null;

      // Write initial state to URL
      this.writeFiltersToURL();
    }

    // Render the widget
    this.render();
  }

  private render(): void {
    if (!this.container || !this.aggregatedData) return;

    // Create container structure
    this.container.innerHTML = '';

    // Create legend first (at the top)
    const legend = this.createLegend();
    this.container.appendChild(legend);

    // Create filters container
    const filtersContainer = document.createElement('div');
    filtersContainer.className = 'controls stock-filters';
    this.container.appendChild(filtersContainer);

    // Create filters
    this.createFilters(filtersContainer);

    // Create iteration info display
    const iterationInfo = this.createIterationInfo();
    this.container.appendChild(iterationInfo);

    // Create table container
    const tableContainer = document.createElement('div');
    tableContainer.className = 'stock-table-container';
    this.container.appendChild(tableContainer);

    // Build the table
    this.buildTable(tableContainer);
  }

  private createFilters(container: HTMLElement): void {
    if (!this.aggregatedData) return;

    // Helper function to create a multi-select checkbox filter
    const createCheckboxFilter = (
      label: string,
      options: Set<string>,
      currentSelection: Set<string>,
      onChange: (selected: Set<string>) => void
    ): void => {
      const group = document.createElement('div');
      group.className = 'control-group filter-group';

      const labelEl = document.createElement('label');
      labelEl.textContent = label;
      group.appendChild(labelEl);

      const checkboxContainer = document.createElement('div');
      checkboxContainer.className = 'checkbox-container';
      group.appendChild(checkboxContainer);

      // Add "Select All" / "Clear All" buttons
      const buttonContainer = document.createElement('div');
      buttonContainer.className = 'filter-buttons';

      const selectAllBtn = document.createElement('button');
      selectAllBtn.textContent = 'All';
      selectAllBtn.type = 'button';
      selectAllBtn.className = 'filter-btn';
      selectAllBtn.addEventListener('click', () => {
        const checkboxes = checkboxContainer.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
        checkboxes.forEach(cb => cb.checked = true);
        onChange(new Set(options));
        this.writeFiltersToURL();
        this.render();
      });

      const clearAllBtn = document.createElement('button');
      clearAllBtn.textContent = 'None';
      clearAllBtn.type = 'button';
      clearAllBtn.className = 'filter-btn';
      clearAllBtn.addEventListener('click', () => {
        const checkboxes = checkboxContainer.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
        checkboxes.forEach(cb => cb.checked = false);
        onChange(new Set());
        this.writeFiltersToURL();
        this.render();
      });

      buttonContainer.appendChild(selectAllBtn);
      buttonContainer.appendChild(clearAllBtn);
      checkboxContainer.appendChild(buttonContainer);

      // Create checkboxes for each option (sorted)
      const sortedOptions = Array.from(options).sort();
      for (const opt of sortedOptions) {
        const checkboxLabel = document.createElement('label');
        checkboxLabel.className = 'checkbox-label';

        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.value = opt;
        checkbox.checked = currentSelection.has(opt);

        checkbox.addEventListener('change', () => {
          const newSelection = new Set<string>();
          const allCheckboxes = checkboxContainer.querySelectorAll<HTMLInputElement>('input[type="checkbox"]:not(.select-all)');
          allCheckboxes.forEach(cb => {
            if (cb.checked) {
              newSelection.add(cb.value);
            }
          });
          onChange(newSelection);
          this.writeFiltersToURL();
          this.render();
        });

        const span = document.createElement('span');
        span.textContent = opt;

        checkboxLabel.appendChild(checkbox);
        checkboxLabel.appendChild(span);
        checkboxContainer.appendChild(checkboxLabel);
      }

      container.appendChild(group);
    };

    // Region filter
    createCheckboxFilter(
      'Region:',
      this.aggregatedData.regions,
      this.config.regionFilter,
      (selected) => {
        this.config.regionFilter = selected;
      }
    );

    // City filter
    createCheckboxFilter(
      'City:',
      this.aggregatedData.areaNames,
      this.config.cityFilter,
      (selected) => {
        this.config.cityFilter = selected;
      }
    );

    // Good filter
    createCheckboxFilter(
      'Good:',
      this.aggregatedData.goodNames,
      this.config.goodFilter,
      (selected) => {
        this.config.goodFilter = selected;
      }
    );

    // Latest iteration checkbox
    const latestIterGroup = document.createElement('div');
    latestIterGroup.className = 'control-group';

    const latestIterLabel = document.createElement('label');
    latestIterLabel.className = 'checkbox-label';

    const latestIterCheckbox = document.createElement('input');
    latestIterCheckbox.type = 'checkbox';
    latestIterCheckbox.checked = this.config.onlyLatestIteration;
    latestIterCheckbox.addEventListener('change', () => {
      this.config.onlyLatestIteration = latestIterCheckbox.checked;
      this.writeFiltersToURL();
      this.render();
    });

    const latestIterSpan = document.createElement('span');
    latestIterSpan.textContent = 'Only show latest iteration';

    latestIterLabel.appendChild(latestIterCheckbox);
    latestIterLabel.appendChild(latestIterSpan);
    latestIterGroup.appendChild(latestIterLabel);

    container.appendChild(latestIterGroup);

    // Legend filter
    const legendLabels: Record<string, string> = {
      'unavailable': 'Unavailable (Stock = 0)',
      'red': 'Red (Low Stock)',
      'green': 'Green (Surplus)',
      'bold-green': 'Bold Green (High Surplus)',
    };

    const legendGroup = document.createElement('div');
    legendGroup.className = 'control-group filter-group';

    const legendLabel = document.createElement('label');
    legendLabel.textContent = 'Show goods with status:';
    legendGroup.appendChild(legendLabel);

    const legendCheckboxContainer = document.createElement('div');
    legendCheckboxContainer.className = 'checkbox-container';
    legendGroup.appendChild(legendCheckboxContainer);

    // Add "All" / "None" buttons
    const legendButtonContainer = document.createElement('div');
    legendButtonContainer.className = 'filter-buttons';

    const legendAllBtn = document.createElement('button');
    legendAllBtn.textContent = 'All';
    legendAllBtn.type = 'button';
    legendAllBtn.className = 'filter-btn';
    legendAllBtn.addEventListener('click', () => {
      this.config.legendFilter = new Set();
      this.writeFiltersToURL();
      this.render();
    });

    const legendNoneBtn = document.createElement('button');
    legendNoneBtn.textContent = 'None';
    legendNoneBtn.type = 'button';
    legendNoneBtn.className = 'filter-btn';
    legendNoneBtn.addEventListener('click', () => {
      const checkboxes = legendCheckboxContainer.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
      checkboxes.forEach(cb => cb.checked = false);
      this.config.legendFilter = new Set();
      this.writeFiltersToURL();
      this.render();
    });

    legendButtonContainer.appendChild(legendAllBtn);
    legendButtonContainer.appendChild(legendNoneBtn);
    legendCheckboxContainer.appendChild(legendButtonContainer);

    // Create checkboxes for each legend type (in logical order)
    const legendOrder = ['unavailable', 'red', 'green', 'bold-green'];
    for (const legendType of legendOrder) {
      const checkboxLabel = document.createElement('label');
      checkboxLabel.className = 'checkbox-label';

      const checkbox = document.createElement('input');
      checkbox.type = 'checkbox';
      checkbox.value = legendType;
      checkbox.checked = this.config.legendFilter.has(legendType);

      checkbox.addEventListener('change', () => {
        const newSelection = new Set<string>();
        const allCheckboxes = legendCheckboxContainer.querySelectorAll<HTMLInputElement>('input[type="checkbox"]:not(.select-all)');
        allCheckboxes.forEach(cb => {
          if (cb.checked) {
            newSelection.add(cb.value);
          }
        });
        this.config.legendFilter = newSelection;
        this.writeFiltersToURL();
        this.render();
      });

      const span = document.createElement('span');
      span.textContent = legendLabels[legendType];

      checkboxLabel.appendChild(checkbox);
      checkboxLabel.appendChild(span);
      legendCheckboxContainer.appendChild(checkboxLabel);
    }

    container.appendChild(legendGroup);

    // Category filter (if we have categories)
    if (this.aggregatedData.categories.size > 0) {
      createCheckboxFilter(
        'Request category:',
        this.aggregatedData.categories,
        this.config.categoryFilter,
        (selected) => {
          this.config.categoryFilter = selected;
        }
      );
    }

    // Exact reason filter (if we have exact reasons)
    if (this.aggregatedData.exactReasons.size > 0) {
      createCheckboxFilter(
        'Exact reason:',
        this.aggregatedData.exactReasons,
        this.config.reasonFilter,
        (selected) => {
          this.config.reasonFilter = selected;
        }
      );
    }

    // Sort controls
    const sortGroup = document.createElement('div');
    sortGroup.className = 'control-group';

    const sortLabel = document.createElement('label');
    sortLabel.textContent = 'Sort by:';
    sortGroup.appendChild(sortLabel);

    const sortSelect = document.createElement('select');
    sortSelect.innerHTML = `
      <option value="stock">Stock (descending)</option>
      <option value="request">Request (descending)</option>
    `;
    sortSelect.value = this.config.sortBy;
    sortSelect.addEventListener('change', () => {
      this.config.sortBy = sortSelect.value as 'stock' | 'request';
      this.writeFiltersToURL();
      this.render();
    });
    sortGroup.appendChild(sortSelect);

    container.appendChild(sortGroup);
  }

  private buildTable(container: HTMLElement): void {
    if (!this.aggregatedData) return;

    const { stocks, latestIterations } = this.aggregatedData;

    // Build region map for each area first (to filter by region)
    const areaRegionMap = new Map<string, string>();
    for (const goodMap of stocks.values()) {
      for (const [areaName, data] of goodMap.entries()) {
        if (!areaRegionMap.has(areaName)) {
          areaRegionMap.set(areaName, data.region);
        }
      }
    }

    // Filter goods and areas based on current filters
    const filteredGoods = Array.from(this.aggregatedData.goodNames)
      .filter(good => this.config.goodFilter.has(good));
    const filteredAreas = Array.from(this.aggregatedData.areaNames)
      .filter(area => {
        // Filter by city filter
        if (!this.config.cityFilter.has(area)) return false;

        // Filter by region filter
        if (this.config.regionFilter.size > 0) {
          const areaRegion = areaRegionMap.get(area);
          if (!areaRegion || !this.config.regionFilter.has(areaRegion)) {
            return false;
          }
        }

        return true;
      })
      .sort((a, b) => {
        // Sort by region first (custom order: OW, NW, EN, AR, CT), then by area name
        const regionOrder = ['OW', 'NW', 'EN', 'AR', 'CT'];
        const regionA = areaRegionMap.get(a) || '';
        const regionB = areaRegionMap.get(b) || '';

        if (regionA !== regionB) {
          const indexA = regionOrder.indexOf(regionA);
          const indexB = regionOrder.indexOf(regionB);
          // If region not in order list, put at end
          const priorityA = indexA === -1 ? 999 : indexA;
          const priorityB = indexB === -1 ? 999 : indexB;
          return priorityA - priorityB;
        }

        return a.localeCompare(b);
      });

    // Helper function to check if a good is unavailable everywhere (stock = 0 or no data in all areas)
    const isGoodUnavailableEverywhere = (goodName: string): boolean => {
      const goodMap = stocks.get(goodName);
      if (!goodMap) return true; // No data at all

      // Check if there's any area with stock > 0
      for (const areaName of filteredAreas) {
        const data = goodMap.get(areaName);
        if (!data) continue;

        // Apply region filter
        if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
          continue;
        }

        // Check if data is from latest iteration (if filter enabled)
        const areaRegion = data.region;
        const latestIter = latestIterations.get(areaRegion);
        if (this.config.onlyLatestIteration && latestIter && data.iteration !== latestIter) {
          continue;
        }

        // If we find any area with stock > 0, the good is not unavailable everywhere
        if (data.stock > 0) {
          return false;
        }
      }

      return true; // No area has stock > 0
    };

    // Helper function to get the highest priority category for a good
    const getCategoryPriority = (goodName: string): number => {
      const goodMap = stocks.get(goodName);
      if (!goodMap) return 999; // No data, put at end

      const reasons = getGoodReasons(goodMap);
      if (reasons.length === 0) return 999; // No reasons, put at end

      // Check for each category (priority order: Construction > Population > Production > others)
      for (const reason of reasons) {
        const categoryMatch = reason.match(/^([^/]+)/);
        if (categoryMatch) {
          const category = categoryMatch[1].toLowerCase();
          if (category.startsWith('c')) return 0; // Construction
        }
      }

      for (const reason of reasons) {
        const categoryMatch = reason.match(/^([^/]+)/);
        if (categoryMatch) {
          const category = categoryMatch[1].toLowerCase();
          if (category.startsWith('po')) return 1; // Population
        }
      }

      for (const reason of reasons) {
        const categoryMatch = reason.match(/^([^/]+)/);
        if (categoryMatch) {
          const category = categoryMatch[1].toLowerCase();
          if (category.startsWith('pr')) return 2; // Production
        }
      }

      return 3; // Other categories
    };

    // Sort goods based on sort configuration
    if (this.config.sortByCity && this.config.sortOrder) {
      // Sort by specific city's values
      filteredGoods.sort((a, b) => {
        const getValue = (goodName: string): number => {
          const goodMap = stocks.get(goodName);
          if (!goodMap) return 0;

          const data = goodMap.get(this.config.sortByCity!);
          if (!data) return 0;

          // Check if we should use this data based on filters
          if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
            return 0;
          }

          const areaRegion = data.region;
          const latestIter = latestIterations.get(areaRegion);
          if (this.config.onlyLatestIteration && latestIter && data.iteration !== latestIter) {
            return 0;
          }

          return data[this.config.sortBy];
        };

        const aVal = getValue(a);
        const bVal = getValue(b);

        // Sort based on order
        if (this.config.sortOrder === 'asc') {
          return aVal - bVal; // Ascending (lower values first)
        } else {
          return bVal - aVal; // Descending (higher values first)
        }
      });
    } else {
      // No city selected - sort by availability, then category, then alphabetically
      filteredGoods.sort((a, b) => {
        // First, check if goods are unavailable everywhere
        const aUnavailable = isGoodUnavailableEverywhere(a);
        const bUnavailable = isGoodUnavailableEverywhere(b);

        if (aUnavailable !== bUnavailable) {
          // Put unavailable goods at the end
          return aUnavailable ? 1 : -1;
        }

        // Both available or both unavailable - sort by category priority
        const aPriority = getCategoryPriority(a);
        const bPriority = getCategoryPriority(b);

        if (aPriority !== bPriority) {
          return aPriority - bPriority;
        }

        // Within same category, sort alphabetically
        return a.localeCompare(b);
      });
    }

    if (filteredAreas.length === 0) {
      container.innerHTML = '<div class="error">No cities selected</div>';
      return;
    }

    // Create table
    const table = document.createElement('table');
    table.className = 'stock-table';

    // Create header
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    // First column: Good name
    const goodHeader = document.createElement('th');
    goodHeader.textContent = 'Good';
    goodHeader.className = 'stock-good-header';
    headerRow.appendChild(goodHeader);

    // Area columns (clickable for sorting)
    for (const areaName of filteredAreas) {
      const areaHeader = document.createElement('th');
      areaHeader.className = 'stock-area-header';

      // Add sort indicator if this column is being sorted
      let indicator = '';
      let sortState: 'none' | 'asc' | 'desc' = 'none';
      if (this.config.sortByCity === areaName && this.config.sortOrder) {
        sortState = this.config.sortOrder;
        indicator = this.config.sortOrder === 'asc' ? ' ^' : ' v';
        areaHeader.classList.add('stock-sort-active');
      }

      areaHeader.textContent = areaName + indicator;

      // Make clickable for sorting
      areaHeader.style.cursor = 'pointer';
      const nextState = sortState === 'none' ? 'asc' : sortState === 'asc' ? 'desc' : 'none';
      const nextIndicator = nextState === 'asc' ? '^' : nextState === 'desc' ? 'v' : 'none';
      areaHeader.title = `Click to sort by ${areaName}'s ${this.config.sortBy} (${nextIndicator})`;

      // Add click handler - cycles through: none → asc → desc → none
      areaHeader.addEventListener('click', () => {
        if (this.config.sortByCity === areaName) {
          // Already sorting by this city - cycle through states
          if (this.config.sortOrder === 'asc') {
            this.config.sortOrder = 'desc';
          } else if (this.config.sortOrder === 'desc') {
            // Reset to no sort
            this.config.sortByCity = null;
            this.config.sortOrder = null;
          }
        } else {
          // Start sorting by this city (ascending)
          this.config.sortByCity = areaName;
          this.config.sortOrder = 'asc';
        }
        this.writeFiltersToURL();
        this.render();
      });

      headerRow.appendChild(areaHeader);
    }

    thead.appendChild(headerRow);
    table.appendChild(thead);

    // Create body
    const tbody = document.createElement('tbody');

    for (const goodName of filteredGoods) {
      const goodMap = stocks.get(goodName);
      if (!goodMap) continue;

      // Check if this good has data for any filtered area
      const hasDataInFilteredAreas = filteredAreas.some(area => {
        const data = goodMap.get(area);
        if (!data) return false;

        // Apply region filter
        if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
          return false;
        }

        return true;
      });

      if (!hasDataInFilteredAreas) continue;

      // Apply legend filter if active
      if (this.config.legendFilter.size > 0) {
        let matchesLegendFilter = false;

        for (const areaName of filteredAreas) {
          const data = goodMap.get(areaName);
          if (!data) continue;

          // Apply region filter
          if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
            continue;
          }

          // Check if data is from latest iteration (if filter enabled)
          const areaRegion = data.region;
          const latestIter = latestIterations.get(areaRegion);
          if (this.config.onlyLatestIteration && latestIter && data.iteration !== latestIter) {
            continue;
          }

          // Check if this data matches any selected legend type
          const classification = classifyStock(data.stock, data.request);
          if (this.config.legendFilter.has(classification)) {
            matchesLegendFilter = true;
            break;
          }
        }

        if (!matchesLegendFilter) continue;
      }

      // Apply category filter if active
      if (this.config.categoryFilter.size > 0) {
        let matchesCategoryFilter = false;

        for (const areaName of filteredAreas) {
          const data = goodMap.get(areaName);
          if (!data || !data.reasons) continue;

          // Apply region filter
          if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
            continue;
          }

          // Check if data is from latest iteration (if filter enabled)
          const areaRegion = data.region;
          const latestIter = latestIterations.get(areaRegion);
          if (this.config.onlyLatestIteration && latestIter && data.iteration !== latestIter) {
            continue;
          }

          // Check if any reason matches any selected category
          for (const reason of data.reasons) {
            const categoryMatch = reason.match(/^([^/]+)/);
            if (categoryMatch && this.config.categoryFilter.has(categoryMatch[1])) {
              matchesCategoryFilter = true;
              break;
            }
          }

          if (matchesCategoryFilter) break;
        }

        if (!matchesCategoryFilter) continue;
      }

      // Apply exact reason filter if active
      if (this.config.reasonFilter.size > 0) {
        let matchesReasonFilter = false;

        for (const areaName of filteredAreas) {
          const data = goodMap.get(areaName);
          if (!data || !data.reasons) continue;

          // Apply region filter
          if (this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
            continue;
          }

          // Check if data is from latest iteration (if filter enabled)
          const areaRegion = data.region;
          const latestIter = latestIterations.get(areaRegion);
          if (this.config.onlyLatestIteration && latestIter && data.iteration !== latestIter) {
            continue;
          }

          // Check if any reason matches any selected exact reason
          for (const reason of data.reasons) {
            if (this.config.reasonFilter.has(reason)) {
              matchesReasonFilter = true;
              break;
            }
          }

          if (matchesReasonFilter) break;
        }

        if (!matchesReasonFilter) continue;
      }

      const row = document.createElement('tr');

      // Good name cell with icon and reason codes
      const goodCell = document.createElement('td');
      goodCell.className = 'stock-good-cell';
      const iconPath = getGoodIconPath(goodName);

      // Get all reasons for this good and generate abbreviations
      const allReasons = getGoodReasons(goodMap);
      const hasReasons = allReasons.length > 0;
      const reasonCodes = hasReasons
        ? allReasons.map(r => abbreviateReason(r)).join(' | ')
        : '';

      // Track expand state for good cell
      const goodCellKey = `good:${goodName}`;
      const isGoodExpanded = this.expandedCells.has(goodCellKey);
      const expandIndicator = hasReasons ? (isGoodExpanded ? ' \u25BC' : ' \u25B6') : '';

      // Build reasons tree if expanded
      let goodReasonsHtml = '';
      if (hasReasons && isGoodExpanded) {
        const tree = buildReasonTree(allReasons);
        const reasonsList = tree
          .map(({ category, details }) => {
            if (details.length === 0) {
              return `<div class="reason-item reason-category-only">${category}</div>`;
            } else {
              const detailsHtml = details
                .map((detail) => `<div class="reason-item reason-detail">${detail}</div>`)
                .join('');
              return `<div class="reason-item reason-category">${category}</div>${detailsHtml}`;
            }
          })
          .join('');
        goodReasonsHtml = `<div class="stock-reasons">${reasonsList}</div>`;
      }

      goodCell.innerHTML = `
        <div class="good-cell-content ${hasReasons ? 'good-cell-expandable' : ''}" ${hasReasons ? `data-cell-key="${goodCellKey}"` : ''}>
          <div class="good-cell-main">
            <img src="${iconPath}" class="good-icon" onerror="this.style.display='none'" alt="${goodName}" title="${goodName}">
            <span class="good-name">${goodName}</span>${expandIndicator}
            ${reasonCodes ? `<span class="reason-codes">${reasonCodes}</span>` : ''}
          </div>
          ${goodReasonsHtml}
        </div>
      `;

      // Add click handler for expandable good cells
      if (hasReasons) {
        goodCell.addEventListener('click', () => {
          if (this.expandedCells.has(goodCellKey)) {
            this.expandedCells.delete(goodCellKey);
          } else {
            this.expandedCells.add(goodCellKey);
          }
          this.render();
        });
        goodCell.style.cursor = 'pointer';
      }

      row.appendChild(goodCell);

      // Area cells
      for (const areaName of filteredAreas) {
        const data = goodMap.get(areaName);
        const areaRegion = areaRegionMap.get(areaName);
        const latestIteration = areaRegion ? latestIterations.get(areaRegion) : undefined;

        // Apply region filter
        let filteredData: StockData | null | undefined = data;
        if (data && this.config.regionFilter.size > 0 && !this.config.regionFilter.has(data.region)) {
          filteredData = null;
        }

        const cellKey = `${goodName}:${areaName}`;
        const isExpanded = this.expandedCells.has(cellKey);

        const cell = document.createElement('td');
        cell.className = 'stock-data-cell';
        cell.innerHTML = formatStockCell(
          filteredData,
          latestIteration,
          this.config.onlyLatestIteration,
          cellKey,
          isExpanded
        );

        // Add click handler for expandable cells
        if (filteredData?.reasons && filteredData.reasons.length > 0) {
          cell.addEventListener('click', () => {
            // Toggle expanded state
            if (this.expandedCells.has(cellKey)) {
              this.expandedCells.delete(cellKey);
            } else {
              this.expandedCells.add(cellKey);
            }
            // Re-render to show/hide reasons
            this.render();
          });
          cell.style.cursor = 'pointer';
        }

        row.appendChild(cell);
      }

      tbody.appendChild(row);
    }

    table.appendChild(tbody);
    container.appendChild(table);
  }

  private createLegend(): HTMLElement {
    const legend = document.createElement('div');
    legend.className = 'stock-legend';
    legend.innerHTML = `
      <h3>Legend</h3>
      <div class="legend-container">
        <div class="legend-categories">
          <div><span class="reason-cat-population">Po</span>: Population</div>
          <div><span class="reason-cat-production">Pr</span>: Production</div>
          <div><span class="reason-cat-construction">C</span>: Construction</div>
        </div>
        <div class="legend-separator">|</div>
        <div class="legend-items">
          <div><span class="stock-high-bold">Bold Green</span>: Stock &ge; 2× Request</div>
          <div><span class="stock-high">Green</span>: Stock &ge; Request</div>
          <div><span class="stock-low">Red</span>: Stock &lt; Request</div>
          <div><span class="stock-unavailable">Unavailable</span>: Stock = 0 (not available anywhere)</div>
          <div><span class="request-ok">Blue</span>: Request (stock OK)</div>
          <div><span class="request-alert">Bold Blue</span>: Request (stock low)</div>
          <div><span class="stock-flight">(+X/-Y)</span>: In-flight goods (incoming/outgoing)</div>
          <div><span class="stock-outdated">*</span>: Data from previous iteration (not latest)</div>
          <div><span style="color: var(--text-primary)">▶/▼</span>: Click to expand/collapse reasons</div>
        </div>
      </div>
    `;
    return legend;
  }

  private createIterationInfo(): HTMLElement {
    const iterationInfo = document.createElement('div');
    iterationInfo.className = 'stock-iteration-info';

    if (!this.aggregatedData || this.aggregatedData.latestIterations.size === 0) {
      iterationInfo.textContent = 'Latest iterations: None';
      return iterationInfo;
    }

    // Sort regions alphabetically for consistent display
    const sortedRegions = Array.from(this.aggregatedData.latestIterations.entries())
      .sort((a, b) => a[0].localeCompare(b[0]));

    const iterationText = sortedRegions
      .map(([region, iteration]) => `${region}: ${formatIterationTimestamp(iteration, true)}`)
      .join(', ');

    iterationInfo.textContent = `Latest iterations: ${iterationText}`;
    return iterationInfo;
  }

  /**
   * Restore filters from URL state
   */
  private restoreFiltersFromURL(urlState: ReturnType<typeof readStateFromURL>): boolean {
    if (!this.aggregatedData) return false;

    let restored = false;

    if (urlState.stockRegion !== null) {
      const decoded = decodeFilterSet(urlState.stockRegion, this.aggregatedData.regions);
      if (decoded !== null) {
        this.config.regionFilter = decoded;
        restored = true;
      }
    }

    if (urlState.stockCity !== null) {
      const decoded = decodeFilterSet(urlState.stockCity, this.aggregatedData.areaNames);
      if (decoded !== null) {
        this.config.cityFilter = decoded;
        restored = true;
      }
    }

    if (urlState.stockGood !== null) {
      const decoded = decodeFilterSet(urlState.stockGood, this.aggregatedData.goodNames);
      if (decoded !== null) {
        this.config.goodFilter = decoded;
        restored = true;
      }
    }

    if (urlState.stockOnlyLatest !== null) {
      this.config.onlyLatestIteration = urlState.stockOnlyLatest === 'true';
      restored = true;
    }

    if (urlState.stockSortBy !== null) {
      if (urlState.stockSortBy === 'stock' || urlState.stockSortBy === 'request') {
        this.config.sortBy = urlState.stockSortBy;
        restored = true;
      }
    }

    if (urlState.stockSortByCity !== null) {
      // Validate that the city exists in the data
      if (this.aggregatedData.areaNames.has(urlState.stockSortByCity)) {
        this.config.sortByCity = urlState.stockSortByCity;
        restored = true;
      }
    }

    if (urlState.stockLegend !== null) {
      const validLegendTypes = new Set(['unavailable', 'red', 'green', 'bold-green']);
      const decoded = decodeFilterSet(urlState.stockLegend, validLegendTypes);
      if (decoded !== null) {
        this.config.legendFilter = decoded;
        restored = true;
      }
    }

    if (urlState.stockCategory !== null) {
      const decoded = decodeFilterSet(urlState.stockCategory, this.aggregatedData.categories);
      if (decoded !== null) {
        this.config.categoryFilter = decoded;
        restored = true;
      }
    }

    if (urlState.stockReason !== null) {
      const decoded = decodeFilterSet(urlState.stockReason, this.aggregatedData.exactReasons);
      if (decoded !== null) {
        this.config.reasonFilter = decoded;
        restored = true;
      }
    }

    return restored;
  }

  /**
   * Write current filter state to URL
   */
  private writeFiltersToURL(): void {
    if (!this.aggregatedData) return;

    const validLegendTypes = new Set(['unavailable', 'red', 'green', 'bold-green']);

    writeStateToURL({
      stockRegion: encodeFilterSet(this.config.regionFilter, this.aggregatedData.regions),
      stockCity: encodeFilterSet(this.config.cityFilter, this.aggregatedData.areaNames),
      stockGood: encodeFilterSet(this.config.goodFilter, this.aggregatedData.goodNames),
      stockLegend: encodeFilterSet(this.config.legendFilter, validLegendTypes),
      stockCategory: encodeFilterSet(this.config.categoryFilter, this.aggregatedData.categories),
      stockReason: encodeFilterSet(this.config.reasonFilter, this.aggregatedData.exactReasons),
      stockOnlyLatest: this.config.onlyLatestIteration ? 'true' : 'false',
      stockSortBy: this.config.sortBy,
      stockSortByCity: this.config.sortByCity,
    });
  }

  destroy(): void {
    this.container = null;
    this.aggregatedData = null;
  }
}
