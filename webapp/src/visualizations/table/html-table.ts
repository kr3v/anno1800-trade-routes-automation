/**
 * HTML table implementation of IDataTable
 */

import type {
  IDataTable,
  TableOptions,
  TableRow,
  CellStyle,
} from '../types';

export class HtmlDataTable implements IDataTable {
  private container: HTMLElement | null = null;
  private options: TableOptions;
  private data: TableRow[] = [];

  constructor(options: TableOptions) {
    this.options = options;
  }

  mount(container: HTMLElement): void {
    this.container = container;
    this.render();
  }

  setData(rows: TableRow[]): void {
    this.data = rows;
    this.render();
  }

  configure(options: Partial<TableOptions>): void {
    this.options = { ...this.options, ...options };
    this.render();
  }

  sort(columnId: string, direction?: 'asc' | 'desc'): void {
    const currentDir = this.options.sortDirection ?? 'asc';
    const newDir = direction ?? (currentDir === 'asc' ? 'desc' : 'asc');

    this.options.sortColumn = columnId;
    this.options.sortDirection = newDir;

    this.data.sort((a, b) => {
      const aVal = a[columnId];
      const bVal = b[columnId];

      if (aVal === bVal) return 0;
      if (aVal === null || aVal === undefined) return 1;
      if (bVal === null || bVal === undefined) return -1;

      const cmp = aVal < bVal ? -1 : 1;
      return newDir === 'asc' ? cmp : -cmp;
    });

    this.render();
  }

  destroy(): void {
    if (this.container) {
      this.container.innerHTML = '';
    }
    this.container = null;
  }

  private render(): void {
    if (!this.container) return;

    // Create table structure
    const table = document.createElement('table');
    table.className = 'trade-table';

    // Create header
    const thead = document.createElement('thead');
    const headerRow = document.createElement('tr');

    for (const column of this.options.columns) {
      const th = document.createElement('th');
      th.textContent = column.label;
      th.style.textAlign = column.align ?? 'left';
      if (column.width) th.style.width = column.width;

      if (column.sortable) {
        th.style.cursor = 'pointer';
        th.onclick = () => this.sort(column.id);

        if (this.options.sortColumn === column.id) {
          th.textContent += this.options.sortDirection === 'asc' ? ' ▲' : ' ▼';
        }
      }

      headerRow.appendChild(th);
    }

    thead.appendChild(headerRow);
    table.appendChild(thead);

    // Create body
    const tbody = document.createElement('tbody');

    if (this.data.length === 0) {
      const emptyRow = document.createElement('tr');
      const emptyCell = document.createElement('td');
      emptyCell.colSpan = this.options.columns.length;
      emptyCell.textContent = this.options.emptyMessage ?? 'No data';
      emptyCell.style.textAlign = 'center';
      emptyCell.style.fontStyle = 'italic';
      emptyRow.appendChild(emptyCell);
      tbody.appendChild(emptyRow);
    } else {
      for (const row of this.data) {
        const tr = document.createElement('tr');

        for (const column of this.options.columns) {
          const td = document.createElement('td');
          const value = row[column.id];

          // Apply formatter if provided
          if (column.formatter) {
            const formatted = column.formatter(value, row);
            if (typeof formatted === 'string') {
              td.innerHTML = formatted;
            } else {
              td.appendChild(formatted);
            }
          } else {
            td.textContent = value != null ? String(value) : '';
          }

          td.style.textAlign = column.align ?? 'left';

          // Apply cell styler if provided
          if (this.options.cellStyler) {
            const style = this.options.cellStyler(value, row, column);
            if (style) {
              this.applyStyle(td, style);
            }
          }

          tr.appendChild(td);
        }

        tbody.appendChild(tr);
      }
    }

    table.appendChild(tbody);

    // Replace content
    this.container.innerHTML = '';
    this.container.appendChild(table);
  }

  private applyStyle(element: HTMLElement, style: CellStyle): void {
    if (style.color) element.style.color = style.color;
    if (style.backgroundColor) element.style.backgroundColor = style.backgroundColor;
    if (style.fontWeight) element.style.fontWeight = style.fontWeight;
  }
}
