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
            {id: 'good', label: 'Good/City', sortable: true},
            ...cities.map(city => ({
                id: city,
                label: city,
                align: 'center' as const,
                formatter: (value: unknown) => this.formatCell(value as { received: number; sent: number } | null),
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
    }

    private formatCell(value: { received: number; sent: number } | null): string {
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

        return parts.join('/');
    }

    destroy(): void {
        this.table?.destroy();
        this.table = null;
        this.container = null;
        this.analysis = null;
    }
}
