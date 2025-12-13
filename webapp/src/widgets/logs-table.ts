/**
 * Logs Table Widget
 * Displays base log entries with filtering capabilities
 */

import type { DataStore } from '@/data-store';
import type { LogEntry } from '@/parsers/base-log';
import { createDataTable, type IDataTable, type TableColumn } from '@/visualizations';
import { encodeFilterSet, decodeFilterSet, writeStateToURL, readStateFromURL } from '@/url-state';

export interface LogsTableConfig {
  // Filter values - empty Set means no filter (show all)
  logTypeFilter: Set<string>; // Log entry types (area_stock, trade_spawn, etc.)
  regionFilter: Set<string>; // Regions (OW, NW, AR, EN, CT)
  iterationFilter: Set<string>; // Iteration numbers
  areaSrcFilter: Set<string>;
  areaDstFilter: Set<string>;
  areaFilterMode: 'AND' | 'OR'; // How to combine areaSrc and areaDst filters
  shipFilter: Set<string>;
  goodFilter: Set<string>;
  iterationTypeFilter: Set<string>; // 'regular' | 'hub'
  otherDataRegex: string; // Regex pattern for filtering "Other Data" column
}

/**
 * Clean up name by replacing underscores with spaces
 */
function cleanName(name: string): string {
  return name.replace(/_/g, ' ');
}

/**
 * Convert good name to icon filename
 * E.g., "Work Clothes" -> "icon_work_clothes.png"
 */
function getGoodIconPath(goodName: string): string {
  const iconName = goodName.toLowerCase().replace(/\s+/g, '_');
  return `/icon_${iconName}.png`;
}

/**
 * Extract unique filter values from log entries
 */
interface FilterOptions {
  logTypes: Set<string>;
  regions: Set<string>;
  iterations: Set<string>;
  areaSrcNames: Set<string>;
  areaDstNames: Set<string>;
  shipNames: Set<string>;
  goodNames: Set<string>;
  iterationTypes: Set<string>;
}

function extractFilterOptions(logs: LogEntry[]): FilterOptions {
  const options: FilterOptions = {
    logTypes: new Set(),
    regions: new Set(),
    iterations: new Set(),
    areaSrcNames: new Set(),
    areaDstNames: new Set(),
    shipNames: new Set(),
    goodNames: new Set(),
    iterationTypes: new Set(),
  };

  for (const log of logs) {
    // Extract log type
    options.logTypes.add(log.type);

    // Extract region
    if (log.region) {
      options.regions.add(log.region);
    }

    // Extract iteration
    if ('iteration' in log && log.iteration !== undefined) {
      options.iterations.add(log.iteration.toString());
    }

    // Extract iteration type (tradeType)
    if ('tradeType' in log && log.tradeType) {
      options.iterationTypes.add(log.tradeType);
    }

    // Extract area source names (cleaned)
    if ('areaSrc' in log && log.areaSrc) {
      options.areaSrcNames.add(cleanName(log.areaSrc.name));
    } else if (log.type === 'area_stock') {
      // For area_stock entries, include the area name
      options.areaSrcNames.add(cleanName(log.areaName));
    }

    // Extract area destination names (cleaned)
    if ('areaDst' in log && log.areaDst) {
      options.areaDstNames.add(cleanName(log.areaDst.name));
    }

    // Extract ship names (cleaned)
    if ('ship' in log && log.ship) {
      options.shipNames.add(cleanName(log.ship.name));
    } else if ('shipName' in log && log.shipName) {
      options.shipNames.add(cleanName(log.shipName));
    }

    // Extract good names (cleaned)
    if ('good' in log && log.good) {
      options.goodNames.add(cleanName(log.good.name));
    } else if ('goodName' in log && log.goodName) {
      options.goodNames.add(cleanName(log.goodName));
    }
  }

  return options;
}

/**
 * Filter log entries based on configuration
 * Empty Set = show nothing
 * All options selected = allow empty values (permissive)
 * Partial selection = only show matching items
 */
function filterLogs(logs: LogEntry[], config: LogsTableConfig, filterOptions: FilterOptions): LogEntry[] {
  // Helper to check if all available options are selected
  const allSelected = (filterSet: Set<string>, availableOptions: Set<string>): boolean => {
    return filterSet.size === availableOptions.size;
  };

  return logs.filter((log) => {
    // Filter by log type (empty set = show nothing, always required)
    if (config.logTypeFilter.size === 0 || !config.logTypeFilter.has(log.type)) {
      return false;
    }

    // Filter by region (allow empty if all selected)
    if (config.regionFilter.size > 0) {
      const region = log.region || null;
      const allRegionsSelected = allSelected(config.regionFilter, filterOptions.regions);
      if (!region) {
        if (!allRegionsSelected) return false; // Empty value not allowed
      } else if (!config.regionFilter.has(region)) {
        return false;
      }
    }

    // Filter by iteration (allow empty if all selected)
    if (config.iterationFilter.size > 0) {
      const iteration = 'iteration' in log && log.iteration !== undefined ? log.iteration.toString() : null;
      const allIterationsSelected = allSelected(config.iterationFilter, filterOptions.iterations);
      if (!iteration) {
        if (!allIterationsSelected) return false; // Empty value not allowed
      } else if (!config.iterationFilter.has(iteration)) {
        return false;
      }
    }

    // Filter by iteration type (allow empty if all selected)
    if (config.iterationTypeFilter.size > 0) {
      const tradeType = 'tradeType' in log ? log.tradeType : null;
      const allIterationTypesSelected = allSelected(config.iterationTypeFilter, filterOptions.iterationTypes);
      if (!tradeType) {
        if (!allIterationTypesSelected) return false; // Empty value not allowed
      } else if (!config.iterationTypeFilter.has(tradeType)) {
        return false;
      }
    }

    // Filter by area source and destination (with AND/OR mode support)
    const hasAreaSrcFilter = config.areaSrcFilter.size > 0;
    const hasAreaDstFilter = config.areaDstFilter.size > 0;

    if (hasAreaSrcFilter || hasAreaDstFilter) {
      // Extract area source
      let areaSrc: string | null = null;
      if ('areaSrc' in log && log.areaSrc) {
        areaSrc = cleanName(log.areaSrc.name);
      } else if (log.type === 'area_stock') {
        areaSrc = cleanName(log.areaName);
      }

      // Extract area destination
      const areaDst = 'areaDst' in log && log.areaDst ? cleanName(log.areaDst.name) : null;

      // Check if all options are selected for each filter
      const allAreaSrcSelected = allSelected(config.areaSrcFilter, filterOptions.areaSrcNames);
      const allAreaDstSelected = allSelected(config.areaDstFilter, filterOptions.areaDstNames);

      // Apply filters based on mode
      if (config.areaFilterMode === 'OR' && hasAreaSrcFilter && hasAreaDstFilter) {
        // OR mode: log passes if it matches EITHER area src OR area dst filter
        const srcMatches = areaSrc
          ? config.areaSrcFilter.has(areaSrc)
          : allAreaSrcSelected;
        const dstMatches = areaDst
          ? config.areaDstFilter.has(areaDst)
          : allAreaDstSelected;

        if (!srcMatches && !dstMatches) {
          return false; // Neither matches, reject
        }
      } else {
        // AND mode (or only one filter is set): both filters must pass independently
        if (hasAreaSrcFilter) {
          if (!areaSrc) {
            if (!allAreaSrcSelected) return false;
          } else if (!config.areaSrcFilter.has(areaSrc)) {
            return false;
          }
        }

        if (hasAreaDstFilter) {
          if (!areaDst) {
            if (!allAreaDstSelected) return false;
          } else if (!config.areaDstFilter.has(areaDst)) {
            return false;
          }
        }
      }
    }

    // Filter by ship name (allow empty if all selected)
    if (config.shipFilter.size > 0) {
      const shipName =
        'ship' in log && log.ship
          ? cleanName(log.ship.name)
          : 'shipName' in log && log.shipName
            ? cleanName(log.shipName)
            : null;
      const allShipsSelected = allSelected(config.shipFilter, filterOptions.shipNames);
      if (!shipName) {
        if (!allShipsSelected) return false; // Empty value not allowed
      } else if (!config.shipFilter.has(shipName)) {
        return false;
      }
    }

    // Filter by good name (allow empty if all selected)
    if (config.goodFilter.size > 0) {
      const goodName =
        'good' in log && log.good
          ? cleanName(log.good.name)
          : 'goodName' in log && log.goodName
            ? cleanName(log.goodName)
            : null;
      const allGoodsSelected = allSelected(config.goodFilter, filterOptions.goodNames);
      if (!goodName) {
        if (!allGoodsSelected) return false; // Empty value not allowed
      } else if (!config.goodFilter.has(goodName)) {
        return false;
      }
    }

    // Filter by "Other Data" regex
    if (config.otherDataRegex) {
      try {
        const regex = new RegExp(config.otherDataRegex, 'i'); // Case-insensitive
        const otherData = formatOtherData(log);
        if (!regex.test(otherData)) {
          return false;
        }
      } catch (e) {
        // Invalid regex - ignore filter
        console.warn('Invalid regex pattern:', config.otherDataRegex, e);
      }
    }

    return true;
  });
}

/**
 * Convert log entry to "other" data string (key=value format)
 */
function formatOtherData(log: LogEntry): string {
  const otherFields: string[] = [];

  // Note: type is now in its own column, so we don't include it here

  // Add loc if available
  if (log.loc) {
    otherFields.push(`loc=${log.loc}`);
  }

  // Note: region, iteration, and amount are now in their own columns

  // Add type-specific fields
  switch (log.type) {
    case 'area_stock':
      otherFields.push(`stock=${log.stock}`);
      otherFields.push(`inFlight=${log.inFlightIn}`);
      otherFields.push(`request=${log.request}`);
      break;

    case 'ship_status':
      otherFields.push(`status=${log.status}`);
      otherFields.push(`oid=${log.oid}`);
      otherFields.push(`route=${log.route}`);
      otherFields.push(`isMoving=${log.isMoving}`);
      otherFields.push(`hasCargo=${log.hasCargo}`);
      break;

    case 'ship_count':
      otherFields.push(`countType=${log.countType}`);
      otherFields.push(`count=${log.count}`);
      break;

    case 'tasks_spawned':
      otherFields.push(`tasksSpawned=${log.tasksSpawned}`);
      break;

    case 'still_available':
      otherFields.push(`shipsAvailable=${log.shipsAvailable}`);
      otherFields.push(`requestsRemaining=${log.requestsRemaining}`);
      break;

    case 'trade_spawn':
    case 'trade_execution':
      // Note: amount is now in its own column
      if ('stage' in log) {
        otherFields.push(`stage=${log.stage}`);
      }
      if ('data' in log && log.data) {
        for (const [key, value] of Object.entries(log.data)) {
          if (value !== undefined) {
            otherFields.push(`${key}=${value}`);
          }
        }
      }
      break;

    case 'iteration_start':
      // No additional fields
      break;

    case 'generic':
      // Just show the raw line
      break;
  }

  return otherFields.join(' ');
}

export class LogsTableWidget {
  private container: HTMLElement | null = null;
  private table: IDataTable | null = null;
  private config: LogsTableConfig = {
    logTypeFilter: new Set(),
    regionFilter: new Set(),
    iterationFilter: new Set(),
    areaSrcFilter: new Set(),
    areaDstFilter: new Set(),
    areaFilterMode: 'AND',
    shipFilter: new Set(),
    goodFilter: new Set(),
    iterationTypeFilter: new Set(),
    otherDataRegex: '',
  };
  private allLogs: LogEntry[] = [];
  private filterOptions: FilterOptions | null = null;

  configure(config: Partial<LogsTableConfig>): void {
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

    this.allLogs = logs;
    this.filterOptions = extractFilterOptions(logs);

    // Try to restore filters from URL first
    const urlState = readStateFromURL();
    const restoredFromURL = this.restoreFiltersFromURL(urlState);

    if (!restoredFromURL) {
      // Initialize filters with defaults (only if not restored from URL)
      // Default: log type filter only shows trade_spawn
      this.config.logTypeFilter = new Set(
        Array.from(this.filterOptions.logTypes).filter(
          (type) => type === 'trade_spawn'
        )
      );
      this.config.regionFilter = new Set(this.filterOptions.regions);
      this.config.iterationFilter = new Set(this.filterOptions.iterations);
      this.config.iterationTypeFilter = new Set(this.filterOptions.iterationTypes);
      this.config.areaSrcFilter = new Set(this.filterOptions.areaSrcNames);
      this.config.areaDstFilter = new Set(this.filterOptions.areaDstNames);
      this.config.shipFilter = new Set(this.filterOptions.shipNames);
      this.config.goodFilter = new Set(this.filterOptions.goodNames);

      // Write initial state to URL
      this.writeFiltersToURL();
    }

    // Render filters and table
    this.render();
  }

  private render(): void {
    if (!this.container || !this.filterOptions) return;

    // Create container structure
    this.container.innerHTML = '';

    // Create filters container
    const filtersContainer = document.createElement('div');
    filtersContainer.className = 'controls logs-filters';
    this.container.appendChild(filtersContainer);

    // Create filters
    this.createFilters(filtersContainer);

    // Create summary
    const summary = document.createElement('div');
    summary.className = 'controls';
    const filteredLogs = filterLogs(this.allLogs, this.config, this.filterOptions);
    summary.innerHTML = `
      <span>Total logs: ${filteredLogs.length} / ${this.allLogs.length}</span>
    `;
    this.container.appendChild(summary);

    // Create table container
    const tableContainer = document.createElement('div');
    tableContainer.className = 'logs-table-container';
    this.container.appendChild(tableContainer);

    // Prepare columns
    const columns: TableColumn[] = [
      { id: 'timestamp', label: 'Timestamp', sortable: true, width: '180px' },
      { id: 'logType', label: 'Log Type', sortable: true, width: '120px' },
      { id: 'region', label: 'Region', sortable: true, width: '80px' },
      { id: 'iteration', label: 'Iteration', sortable: true, width: '100px' },
      { id: 'iterationType', label: 'Iteration Type', sortable: true, width: '100px' },
      { id: 'areaSrc', label: 'Area Src', sortable: true, width: '120px' },
      { id: 'areaDst', label: 'Area Dst', sortable: true, width: '120px' },
      { id: 'ship', label: 'Ship', sortable: true, width: '100px' },
      {
        id: 'good',
        label: 'Good',
        sortable: true,
        width: '180px',
        formatter: (value) => {
          if (!value || value === '') return '';
          const goodName = value as string;
          const iconPath = getGoodIconPath(goodName);
          return `<img src="${iconPath}" class="good-icon" onerror="this.style.display='none'" alt="${goodName}" title="${goodName}"><span>${goodName}</span>`;
        },
      },
      { id: 'amount', label: 'Amount', sortable: true, width: '80px' },
      { id: 'other', label: 'Other Data', sortable: false },
    ];

    // Prepare rows (reversed to show newest first)
    const rows = filteredLogs.reverse().map((log) => {
      // Extract area source
      let areaSrc = '';
      if ('areaSrc' in log && log.areaSrc) {
        areaSrc = cleanName(log.areaSrc.name);
      } else if (log.type === 'area_stock') {
        // For area_stock entries, show the area name in Area Src column
        areaSrc = cleanName(log.areaName);
      }

      // Extract amount
      let amount = '';
      if ('amount' in log && log.amount !== undefined) {
        amount = log.amount.toString();
      }

      return {
        timestamp: log.timestamp?.toLocaleString() ?? '',
        logType: log.type,
        region: log.region ?? '',
        iteration: 'iteration' in log && log.iteration !== undefined ? log.iteration.toString() : '',
        iterationType: 'tradeType' in log && log.tradeType ? log.tradeType : '',
        areaSrc,
        areaDst: 'areaDst' in log && log.areaDst ? cleanName(log.areaDst.name) : '',
        ship:
          'ship' in log && log.ship
            ? cleanName(log.ship.name)
            : 'shipName' in log && log.shipName
              ? cleanName(log.shipName)
              : '',
        good:
          'good' in log && log.good
            ? cleanName(log.good.name)
            : 'goodName' in log && log.goodName
              ? cleanName(log.goodName)
              : '',
        amount,
        other: formatOtherData(log),
      };
    });

    // Create and mount table
    this.table = createDataTable({
      columns,
      emptyMessage: 'No logs found',
    });
    this.table.mount(tableContainer);
    this.table.setData(rows);
  }

  private createFilters(container: HTMLElement): void {
    if (!this.filterOptions) return;

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

    // Create all filters
    createCheckboxFilter(
      'Log Type:',
      this.filterOptions.logTypes,
      this.config.logTypeFilter,
      (selected) => {
        this.config.logTypeFilter = selected;
      }
    );

    createCheckboxFilter(
      'Region:',
      this.filterOptions.regions,
      this.config.regionFilter,
      (selected) => {
        this.config.regionFilter = selected;
      }
    );

    createCheckboxFilter(
      'Iteration:',
      this.filterOptions.iterations,
      this.config.iterationFilter,
      (selected) => {
        this.config.iterationFilter = selected;
      }
    );

    createCheckboxFilter(
      'Iteration Type:',
      this.filterOptions.iterationTypes,
      this.config.iterationTypeFilter,
      (selected) => {
        this.config.iterationTypeFilter = selected;
      }
    );

    createCheckboxFilter(
      'Area Src:',
      this.filterOptions.areaSrcNames,
      this.config.areaSrcFilter,
      (selected) => {
        this.config.areaSrcFilter = selected;
      }
    );

    // Add AND/OR toggle for area filters
    const modeToggleGroup = document.createElement('div');
    modeToggleGroup.className = 'control-group filter-mode-toggle';
    modeToggleGroup.style.cssText = 'display: flex; align-items: center; gap: 8px; padding: 8px 0;';

    const modeLabel = document.createElement('label');
    modeLabel.textContent = 'Area Filter Mode:';
    modeLabel.style.cssText = 'margin: 0; font-weight: bold;';
    modeToggleGroup.appendChild(modeLabel);

    const modeButton = document.createElement('button');
    modeButton.type = 'button';
    modeButton.className = 'filter-mode-btn';
    modeButton.textContent = this.config.areaFilterMode;
    modeButton.style.cssText = 'padding: 4px 12px; cursor: pointer;';
    modeButton.addEventListener('click', () => {
      this.config.areaFilterMode = this.config.areaFilterMode === 'AND' ? 'OR' : 'AND';
      modeButton.textContent = this.config.areaFilterMode;
      this.writeFiltersToURL();
      this.render();
    });

    const modeHint = document.createElement('span');
    modeHint.textContent = '(AND = both must match, OR = either can match)';
    modeHint.style.cssText = 'font-size: 0.9em; color: #666;';
    modeToggleGroup.appendChild(modeButton);
    modeToggleGroup.appendChild(modeHint);

    container.appendChild(modeToggleGroup);

    createCheckboxFilter(
      'Area Dst:',
      this.filterOptions.areaDstNames,
      this.config.areaDstFilter,
      (selected) => {
        this.config.areaDstFilter = selected;
      }
    );

    createCheckboxFilter(
      'Ship:',
      this.filterOptions.shipNames,
      this.config.shipFilter,
      (selected) => {
        this.config.shipFilter = selected;
      }
    );

    createCheckboxFilter(
      'Good:',
      this.filterOptions.goodNames,
      this.config.goodFilter,
      (selected) => {
        this.config.goodFilter = selected;
      }
    );

    // Create regex filter for "Other Data"
    const regexGroup = document.createElement('div');
    regexGroup.className = 'control-group filter-group';

    const regexLabel = document.createElement('label');
    regexLabel.textContent = 'Other Data (regex):';
    regexGroup.appendChild(regexLabel);

    const regexInput = document.createElement('input');
    regexInput.type = 'text';
    regexInput.placeholder = 'e.g., stage=start or stage=(start|completed)';
    regexInput.value = this.config.otherDataRegex;
    regexInput.className = 'regex-input';
    regexInput.addEventListener('input', () => {
      this.config.otherDataRegex = regexInput.value;
      this.writeFiltersToURL();
      this.render();
    });
    regexGroup.appendChild(regexInput);

    container.appendChild(regexGroup);
  }

  /**
   * Restore filters from URL state
   * @returns true if filters were restored from URL, false otherwise
   */
  private restoreFiltersFromURL(urlState: ReturnType<typeof readStateFromURL>): boolean {
    if (!this.filterOptions) return false;

    let restored = false;

    // Restore each filter
    if (urlState.logType !== null) {
      const decoded = decodeFilterSet(urlState.logType, this.filterOptions.logTypes);
      if (decoded !== null) {
        this.config.logTypeFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logRegion !== null) {
      const decoded = decodeFilterSet(urlState.logRegion, this.filterOptions.regions);
      if (decoded !== null) {
        this.config.regionFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logIteration !== null) {
      const decoded = decodeFilterSet(urlState.logIteration, this.filterOptions.iterations);
      if (decoded !== null) {
        this.config.iterationFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logIterationType !== null) {
      const decoded = decodeFilterSet(urlState.logIterationType, this.filterOptions.iterationTypes);
      if (decoded !== null) {
        this.config.iterationTypeFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logAreaSrc !== null) {
      const decoded = decodeFilterSet(urlState.logAreaSrc, this.filterOptions.areaSrcNames);
      if (decoded !== null) {
        this.config.areaSrcFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logAreaDst !== null) {
      const decoded = decodeFilterSet(urlState.logAreaDst, this.filterOptions.areaDstNames);
      if (decoded !== null) {
        this.config.areaDstFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logShip !== null) {
      const decoded = decodeFilterSet(urlState.logShip, this.filterOptions.shipNames);
      if (decoded !== null) {
        this.config.shipFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logGood !== null) {
      const decoded = decodeFilterSet(urlState.logGood, this.filterOptions.goodNames);
      if (decoded !== null) {
        this.config.goodFilter = decoded;
        restored = true;
      }
    }

    if (urlState.logAreaMode !== null) {
      if (urlState.logAreaMode === 'AND' || urlState.logAreaMode === 'OR') {
        this.config.areaFilterMode = urlState.logAreaMode;
        restored = true;
      }
    }

    if (urlState.logOtherDataRegex !== null) {
      this.config.otherDataRegex = urlState.logOtherDataRegex;
      restored = true;
    }

    return restored;
  }

  /**
   * Write current filter state to URL
   */
  private writeFiltersToURL(): void {
    if (!this.filterOptions) return;

    writeStateToURL({
      logType: encodeFilterSet(this.config.logTypeFilter, this.filterOptions.logTypes),
      logRegion: encodeFilterSet(this.config.regionFilter, this.filterOptions.regions),
      logIteration: encodeFilterSet(this.config.iterationFilter, this.filterOptions.iterations),
      logIterationType: encodeFilterSet(this.config.iterationTypeFilter, this.filterOptions.iterationTypes),
      logAreaSrc: encodeFilterSet(this.config.areaSrcFilter, this.filterOptions.areaSrcNames),
      logAreaDst: encodeFilterSet(this.config.areaDstFilter, this.filterOptions.areaDstNames),
      logAreaMode: this.config.areaFilterMode !== 'AND' ? this.config.areaFilterMode : null,
      logShip: encodeFilterSet(this.config.shipFilter, this.filterOptions.shipNames),
      logGood: encodeFilterSet(this.config.goodFilter, this.filterOptions.goodNames),
      logOtherDataRegex: this.config.otherDataRegex || null,
    });
  }

  /**
   * Apply filters from current URL state and re-render
   * This is useful when navigating to the logs tab from another widget with specific filters
   */
  applyFiltersFromURL(): void {
    if (!this.filterOptions) return;

    const urlState = readStateFromURL();
    const restored = this.restoreFiltersFromURL(urlState);

    if (restored) {
      this.render();
    }
  }

  destroy(): void {
    this.table?.destroy();
    this.table = null;
    this.container = null;
    this.allLogs = [];
    this.filterOptions = null;
  }
}
