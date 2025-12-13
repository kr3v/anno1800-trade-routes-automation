/**
 * Trade Table Widget
 * Displays trade history in a table with heatmap coloring
 */

import type { DataStore } from '@/data-store';
import {
    analyzeTrades,
    filterTradesByDuration,
    sortCities,
    sortGoods,
    type TradeAnalysis,
} from '@/parsers/trades';
import {createDataTable, type IDataTable, type TableColumn} from '@/visualizations';

export interface TradeTableConfig {
    duration: string | null;
    boldThreshold: number;  // percentage of max for bold
    colorThreshold: number; // percentage of max for color
    onNavigateToLogs?: (filters: { good?: string; city?: string }) => void;
}

const DEFAULT_CONFIG: TradeTableConfig = {
    duration: null,
    boldThreshold: 0.75,
    colorThreshold: 0.25,
};

export class TradeTableWidget {
    private container: HTMLElement | null = null;
    private table: IDataTable | null = null;
    private config: TradeTableConfig = {...DEFAULT_CONFIG};
    private analysis: TradeAnalysis | null = null;

    configure(config: Partial<TradeTableConfig>): void {
        this.config = {...this.config, ...config};
    }

    async mount(container: HTMLElement): Promise<void> {
        this.container = container;
        container.innerHTML = '<div class="tab-placeholder">Loading...</div>';
    }

    async load(
        dataStore: DataStore,
        profileName: string
    ): Promise<void> {
        if (!this.container) return;

        // Get trades from DataStore (already parsed)
        const trades = dataStore.getTrades(profileName);

        if (!trades) {
            this.container.innerHTML = `<div class="error">No trades found for profile: ${profileName}</div>`;
            return;
        }

        if (trades.length === 0) {
            this.container.innerHTML = '<div class="error">No trades recorded</div>';
            return;
        }

        // Filter trades by duration
        const filteredTrades = filterTradesByDuration(trades, this.config.duration);

        // Analyze trades
        this.analysis = analyzeTrades(filteredTrades);

        // Render table
        this.render();
    }

    private render(): void {
        if (!this.container || !this.analysis) return;

        // Prepare columns
        const cities = sortCities(this.analysis.cities, this.analysis);
        const columns: TableColumn[] = [
            {
                id: 'good',
                label: 'Good/City',
                sortable: true,
                formatter: (value: unknown) => {
                    const goodName = value as string;
                    if (this.config.onNavigateToLogs) {
                        return `<span class="clickable-good" data-good="${goodName}">${goodName}</span>`;
                    }
                    return goodName;
                }
            },
            ...cities.map(city => ({
                id: city,
                label: city,
                align: 'center' as const,
                formatter: (value: unknown) => this.formatCell(value as { received: number; sent: number } | null, city),
            })),
        ];

        // Prepare rows
        const goods = sortGoods(this.analysis.goods, this.analysis);
        const rows = goods.map(good => {
            const row: Record<string, unknown> = {good};

            for (const city of cities) {
                const received = this.analysis!.received.get(city)?.get(good)?.amount ?? 0;
                const sent = this.analysis!.sent.get(city)?.get(good)?.amount ?? 0;

                if (received > 0 || sent > 0) {
                    row[city] = {received, sent};
                } else {
                    row[city] = null;
                }
            }

            return row;
        }).filter(row => {
            // Filter out rows with no data
            return cities.some(city => row[city] !== null);
        });

        // Create wrapper
        this.container.innerHTML = '';

        // Add summary
        const summary = document.createElement('div');
        summary.className = 'controls';
        summary.innerHTML = `
      <span>Total trades: ${this.analysis.tradeCount}</span>
      ${this.analysis.timeRange.start ? `<span>From: ${this.analysis.timeRange.start.toLocaleString()}</span>` : ''}
      ${this.analysis.timeRange.end ? `<span>To: ${this.analysis.timeRange.end.toLocaleString()}</span>` : ''}
    `;
        this.container.appendChild(summary);

        // Create table container
        const tableContainer = document.createElement('div');
        tableContainer.className = 'trade-table-container';
        this.container.appendChild(tableContainer);

        // Create and mount table
        this.table = createDataTable({
            columns,
            emptyMessage: 'No trades found',
        });
        this.table.mount(tableContainer);
        this.table.setData(rows);

        // Set up click handlers for navigation
        if (this.config.onNavigateToLogs) {
            this.setupClickHandlers(tableContainer);
        }
    }

    private setupClickHandlers(container: HTMLElement): void {
        // Make city header cells clickable
        const headerCells = container.querySelectorAll('th');
        headerCells.forEach((th, index) => {
            // Skip the first column (Good/City header)
            if (index === 0) return;

            // Get the city name from the header text (excluding sort indicators)
            const cityName = th.textContent?.replace(/\s*[▲▼]\s*$/, '').trim();
            if (!cityName) return;

            // Add clickable class and cursor style
            th.classList.add('clickable-city');
            th.style.cursor = 'pointer';
            th.dataset.city = cityName;
        });

        // Handle clicks on good names, city headers, and cells
        container.addEventListener('click', (e) => {
            const target = e.target as HTMLElement;

            // Click on good name
            if (target.classList.contains('clickable-good')) {
                const good = target.dataset.good;
                if (good && this.config.onNavigateToLogs) {
                    this.config.onNavigateToLogs({ good });
                }
                return;
            }

            // Click on city header
            if (target.classList.contains('clickable-city') && target.tagName === 'TH') {
                const city = target.dataset.city;
                if (city && this.config.onNavigateToLogs) {
                    this.config.onNavigateToLogs({ city });
                }
                return;
            }

            // Click on cell - check if target or any parent is clickable-cell
            const clickableCell = target.closest('.clickable-cell') as HTMLElement;
            if (clickableCell) {
                const city = clickableCell.dataset.city;
                // Find the good name by traversing up to the row and finding the first cell
                const row = clickableCell.closest('tr');
                if (row && city) {
                    const firstCell = row.querySelector('td:first-child .clickable-good');
                    const good = firstCell?.getAttribute('data-good');
                    if (good && this.config.onNavigateToLogs) {
                        this.config.onNavigateToLogs({ good, city });
                    }
                }
                return;
            }
        });
    }

    private formatCell(value: { received: number; sent: number } | null, city: string): string {
        if (!value || (value.received === 0 && value.sent === 0)) {
            return '';
        }

        const parts: string[] = [];
        const maxAmount = this.analysis?.maxAmount ?? 1;

        if (value.received > 0) {
            const pct = value.received / maxAmount;
            const boldClass = pct >= this.config.boldThreshold ? ' cell-bold' : '';
            const colorClass = pct >= this.config.colorThreshold ? ' cell-received' : '';
            parts.push(`<span class="${colorClass}${boldClass}">↑${value.received}</span>`);
        }

        if (value.sent > 0) {
            const pct = value.sent / maxAmount;
            const boldClass = pct >= this.config.boldThreshold ? ' cell-bold' : '';
            const colorClass = pct >= this.config.colorThreshold ? ' cell-sent' : '';
            parts.push(`<span class="${colorClass}${boldClass}">${value.sent}↓</span>`);
        }

        const content = parts.join('/');

        // Make cell clickable if navigation callback is provided
        if (this.config.onNavigateToLogs) {
            return `<span class="clickable-cell" data-city="${city}">${content}</span>`;
        }

        return content;
    }

    destroy(): void {
        this.table?.destroy();
        this.table = null;
        this.container = null;
        this.analysis = null;
    }
}
