/**
 * Deficit/Surplus Widget
 * Displays current deficit and surplus goods
 */

import type { FileSystemDirectoryHandle } from '@/file-access';
import { loadDeficitSurplus, type DeficitSurplusData } from '@/parsers/deficit-surplus';
import { loadGoodsNames } from '@/parsers/texts';

export class DeficitSurplusWidget {
  private container: HTMLElement | null = null;
  private data: DeficitSurplusData | null = null;

  async mount(container: HTMLElement): Promise<void> {
    this.container = container;
  }

  async load(dirHandle: FileSystemDirectoryHandle, profileName: string, region: string = 'OW'): Promise<void> {
    if (!this.container) return;

    try {
      const goodsNames = await loadGoodsNames(dirHandle, 'texts.json');
      this.data = await loadDeficitSurplus(dirHandle, profileName, region, goodsNames);
      this.render();
    } catch (error) {
      const msg = error instanceof Error ? error.message : 'Unknown error';
      this.container.innerHTML = `<div class="error">Failed to load deficit/surplus: ${msg}</div>`;
    }
  }

  private render(): void {
    if (!this.container || !this.data) return;

    this.container.innerHTML = '';

    const wrapper = document.createElement('div');
    wrapper.className = 'deficit-surplus';

    // Deficit list
    const deficitDiv = document.createElement('div');
    deficitDiv.className = 'deficit-list';
    deficitDiv.innerHTML = '<h3>Deficit</h3>';

    if (this.data.deficit.length === 0) {
      deficitDiv.innerHTML += '<div class="deficit-item">No deficits</div>';
    } else {
      for (const entry of this.data.deficit) {
        const areasStr = entry.areas
          .sort((a, b) => a.areaName.localeCompare(b.areaName))
          .map(a => `${a.areaName}@${a.amount}`)
          .join(', ');

        const item = document.createElement('div');
        item.className = 'deficit-item';
        item.innerHTML = `<strong>${entry.goodName}</strong>: <span class="cell-sent">${entry.total}</span> (${areasStr})`;
        deficitDiv.appendChild(item);
      }
    }

    // Surplus list
    const surplusDiv = document.createElement('div');
    surplusDiv.className = 'surplus-list';
    surplusDiv.innerHTML = '<h3>Surplus</h3>';

    if (this.data.surplus.length === 0) {
      surplusDiv.innerHTML += '<div class="surplus-item">No surplus</div>';
    } else {
      for (const entry of this.data.surplus) {
        const areasStr = entry.areas
          .sort((a, b) => a.areaName.localeCompare(b.areaName))
          .map(a => `${a.areaName}@${a.amount}`)
          .join(', ');

        const item = document.createElement('div');
        item.className = 'surplus-item';
        item.innerHTML = `<strong>${entry.goodName}</strong>: <span class="cell-received">${entry.total}</span> (${areasStr})`;
        surplusDiv.appendChild(item);
      }
    }

    wrapper.appendChild(deficitDiv);
    wrapper.appendChild(surplusDiv);
    this.container.appendChild(wrapper);
  }

  destroy(): void {
    this.container = null;
    this.data = null;
  }
}
