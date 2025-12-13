/**
 * Deficit/Surplus Widget
 * Displays current deficit and surplus goods
 */

import type { DataStore } from '@/data-store';
import type { DeficitSurplusData } from '@/parsers/deficit-surplus';

export class DeficitSurplusWidget {
  private container: HTMLElement | null = null;
  private data: DeficitSurplusData | null = null;

  async mount(container: HTMLElement): Promise<void> {
    this.container = container;
  }

  async load(dataStore: DataStore, profileName: string, region: string = 'OW'): Promise<void> {
    if (!this.container) return;

    try {
      // Get deficit/surplus data from DataStore (already parsed)
      this.data = dataStore.getDeficitSurplus(profileName, region);

      if (!this.data) {
        this.container.innerHTML = `<div class="error">No deficit/surplus data found for ${profileName} (${region})</div>`;
        return;
      }

      this.render();
    } catch (error) {
      const msg = error instanceof Error ? error.message : 'Unknown error';
      this.container.innerHTML = `<div class="error">Failed to load deficit/surplus: ${msg}</div>`;
    }
  }

  private render(): void {
    if (!this.container || !this.data) return;

    this.container.innerHTML = '';
  }

  destroy(): void {
    this.container = null;
    this.data = null;
  }
}
