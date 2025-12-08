/**
 * Ship Usage Chart Widget
 * Displays ship availability and task spawning over time
 */

import type { DataStore } from '@/data-store';
import {
  calculateMovingAverage,
  calculateStats,
  type ShipLogEntry,
} from '@/parsers/ship-logs';
import { createLineChart, type ILineChart, type SeriesConfig, type TimeSeriesPoint } from '@/visualizations';

export interface ShipUsageConfig {
  region: string;
  movingAverageWindow: number;
  showRawData: boolean;
  showRegular: boolean;
  showHub: boolean;
}

const DEFAULT_CONFIG: ShipUsageConfig = {
  region: 'OW',
  movingAverageWindow: 10,
  showRawData: true,
  showRegular: true,
  showHub: true,
};

const AVAILABLE_REGIONS = ['OW', 'NW', 'AR', 'EN', 'CT'];

const COLORS = {
  regularShips: '#2E86AB',
  regularTasks: '#A23B72',
  hubShips: '#06A77D',
  hubTasks: '#F18F01',
};

export class ShipUsageChartWidget {
  private container: HTMLElement | null = null;
  private chartContainer: HTMLElement | null = null;
  private statsContainer: HTMLElement | null = null;
  private controlsContainer: HTMLElement | null = null;
  private chart: ILineChart | null = null;
  private config: ShipUsageConfig = { ...DEFAULT_CONFIG };
  private dataStore: DataStore | null = null;

  configure(config: Partial<ShipUsageConfig>): void {
    this.config = { ...this.config, ...config };
  }

  async mount(container: HTMLElement): Promise<void> {
    this.container = container;
    container.innerHTML = '<div class="tab-placeholder">Loading...</div>';
  }

  async load(dataStore: DataStore): Promise<void> {
    if (!this.container) return;

    this.dataStore = dataStore;

    try {
      this.renderData();
    } catch (error) {
      const msg = error instanceof Error ? error.message : 'Unknown error';
      this.container.innerHTML = `<div class="error">Failed to load ship usage: ${msg}</div>`;
    }
  }

  private filterEntriesByRegion(entries: ShipLogEntry[]): ShipLogEntry[] {
    return entries.filter(e => e.region === this.config.region);
  }

  private renderData(): void {
    if (!this.container || !this.dataStore) return;

    // Get ship usage data from DataStore (already parsed)
    const data = this.dataStore.getShipUsage();

    if (data.regular.entries.length === 0 && data.hub.entries.length === 0) {
      this.container.innerHTML = '<div class="error">No ship usage logs found</div>';
      return;
    }

    // Filter by region
    const regularFiltered = this.filterEntriesByRegion(data.regular.entries);
    const hubFiltered = this.filterEntriesByRegion(data.hub.entries);

    // Build series
    const series: SeriesConfig[] = [];

    if (this.config.showRegular && regularFiltered.length > 0) {
      series.push(...this.buildSeries(regularFiltered, 'Regular', COLORS.regularShips, COLORS.regularTasks));
    }

    if (this.config.showHub && hubFiltered.length > 0) {
      series.push(...this.buildSeries(hubFiltered, 'Hub', COLORS.hubShips, COLORS.hubTasks));
    }

    // Render
    this.render(series, { regular: { entries: regularFiltered }, hub: { entries: hubFiltered } });
  }

  private buildSeries(
    entries: ShipLogEntry[],
    mode: string,
    shipsColor: string,
    tasksColor: string
  ): SeriesConfig[] {
    const series: SeriesConfig[] = [];

    const shipsData: TimeSeriesPoint[] = entries.map(e => ({
      timestamp: e.timestamp,
      value: e.shipsAvailable,
    }));

    const tasksData: TimeSeriesPoint[] = entries.map(e => ({
      timestamp: e.timestamp,
      value: e.tasksSpawned,
    }));

    // Raw data (faded)
    if (this.config.showRawData) {
      series.push({
        id: `${mode.toLowerCase()}-ships-raw`,
        label: `Ships (${mode})`,
        color: shipsColor,
        data: shipsData,
        lineWidth: 1,
        opacity: 0.4,
        showPoints: true,
        pointSize: 2,
      });

      series.push({
        id: `${mode.toLowerCase()}-tasks-raw`,
        label: `Tasks (${mode})`,
        color: tasksColor,
        data: tasksData,
        lineWidth: 1,
        lineStyle: 'dashed',
        opacity: 0.4,
        showPoints: true,
        pointSize: 2,
      });
    }

    // Moving average (trend)
    if (this.config.movingAverageWindow > 1) {
      const shipsMA = calculateMovingAverage(
        entries.map(e => e.shipsAvailable),
        this.config.movingAverageWindow
      );

      const tasksMA = calculateMovingAverage(
        entries.map(e => e.tasksSpawned),
        this.config.movingAverageWindow
      );

      series.push({
        id: `${mode.toLowerCase()}-ships-trend`,
        label: `Ships (${mode}) - Trend`,
        color: shipsColor,
        data: shipsMA.map((value, i) => ({
          timestamp: entries[i].timestamp,
          value,
        })),
        lineWidth: 3,
        showPoints: false,
      });

      series.push({
        id: `${mode.toLowerCase()}-tasks-trend`,
        label: `Tasks (${mode}) - Trend`,
        color: tasksColor,
        data: tasksMA.map((value, i) => ({
          timestamp: entries[i].timestamp,
          value,
        })),
        lineWidth: 3,
        lineStyle: 'dashed',
        showPoints: false,
      });
    }

    return series;
  }

  private render(
    series: SeriesConfig[],
    data: { regular: { entries: ShipLogEntry[] }; hub: { entries: ShipLogEntry[] } }
  ): void {
    if (!this.container) return;

    this.container.innerHTML = '';

    // Controls container (region selector)
    this.controlsContainer = document.createElement('div');
    this.controlsContainer.className = 'tab-controls';
    this.renderControls();
    this.container.appendChild(this.controlsContainer);

    // Stats container
    this.statsContainer = document.createElement('div');
    this.statsContainer.className = 'controls';
    this.renderStats(data);
    this.container.appendChild(this.statsContainer);

    // Chart container
    this.chartContainer = document.createElement('div');
    this.chartContainer.className = 'chart-container';
    this.container.appendChild(this.chartContainer);

    // Create chart
    this.chart = createLineChart();
    this.chart.mount(this.chartContainer);
    this.chart.configure({
      title: 'Ship Availability & Task Spawning',
      xAxisLabel: 'Time',
      yAxisLabel: 'Count',
      yAxisBothSides: true,
      showGrid: true,
      showLegend: true,
      legendPosition: 'top',
    });
    this.chart.setSeries(series);
  }

  private renderControls(): void {
    if (!this.controlsContainer) return;

    // Region selector group
    const regionGroup = document.createElement('div');
    regionGroup.className = 'control-group';

    const label = document.createElement('label');
    label.textContent = 'Region:';

    const select = document.createElement('select');
    for (const region of AVAILABLE_REGIONS) {
      const option = document.createElement('option');
      option.value = region;
      option.textContent = region;
      option.selected = region === this.config.region;
      select.appendChild(option);
    }

    select.addEventListener('change', () => {
      this.config.region = select.value;
      this.renderData();
    });

    regionGroup.appendChild(label);
    regionGroup.appendChild(select);
    this.controlsContainer.appendChild(regionGroup);

    // Reset zoom button
    const resetButton = document.createElement('button');
    resetButton.textContent = 'Reset Zoom';
    resetButton.addEventListener('click', () => {
      this.chart?.resetZoom?.();
    });
    this.controlsContainer.appendChild(resetButton);
  }

  private renderStats(
    data: { regular: { entries: ShipLogEntry[] }; hub: { entries: ShipLogEntry[] } }
  ): void {
    if (!this.statsContainer) return;

    const parts: string[] = [];

    if (data.regular.entries.length > 0) {
      const stats = calculateStats(data.regular.entries);
      parts.push(`Regular: ${stats.count} iterations, avg ships: ${stats.avgShips.toFixed(1)}, avg tasks: ${stats.avgTasks.toFixed(1)}`);
    }

    if (data.hub.entries.length > 0) {
      const stats = calculateStats(data.hub.entries);
      parts.push(`Hub: ${stats.count} iterations, avg ships: ${stats.avgShips.toFixed(1)}, avg tasks: ${stats.avgTasks.toFixed(1)}`);
    }

    this.statsContainer.innerHTML = parts.map(p => `<span>${p}</span>`).join('');
  }

  destroy(): void {
    this.chart?.destroy();
    this.chart = null;
    this.chartContainer = null;
    this.statsContainer = null;
    this.controlsContainer = null;
    this.container = null;
    this.dataStore = null;
  }
}
