/**
 * Area Visualizer Widget
 * Displays coordinate points on an interactive canvas with cascading filters
 */

import type {FileSystemDirectoryHandle} from '@/file-access';
import {type CoordinatesData, loadCoordinates, loadMultipleCoordinates,} from '@/parsers/coordinates';
import {
    type AreaFilesIndex,
    getCitiesForGameAndRegion,
    getCityDisplayName,
    getRegionsForGame,
    REGIONS,
    scanAreaFiles,
} from '@/parsers/area-files';
import {type CoordinateCanvasOptions, createCoordinateCanvas, type ICoordinateCanvas} from '@/visualizations';
import {writeStateToURL, type AppState} from '@/url-state';

export class AreaVisualizerWidget {
    private container: HTMLElement | null = null;
    private controlsContainer: HTMLElement | null = null;
    private canvasContainer: HTMLElement | null = null;
    private infoContainer: HTMLElement | null = null;
    private canvas: ICoordinateCanvas | null = null;
    private data: CoordinatesData | null = null;
    private options: Partial<CoordinateCanvasOptions> = {};

    // File index
    private index: AreaFilesIndex | null = null;

    // Filter state
    private selectedGame: string | null = null;
    private selectedRegion: string | null = null;  // null = all regions
    private selectedCity: string | null = null;    // null = all cities

    // Saved state from URL (to restore after directory is loaded)
    private savedState: Pick<AppState, 'game' | 'areaRegion' | 'city'> | null = null;

    // UI elements
    private gameSelect: HTMLSelectElement | null = null;
    private regionSelect: HTMLSelectElement | null = null;
    private citySelect: HTMLSelectElement | null = null;

    configure(options: Partial<CoordinateCanvasOptions>): void {
        this.options = {...this.options, ...options};
        this.canvas?.configure(this.options);
    }

    async mount(container: HTMLElement): Promise<void> {
        this.container = container;
        this.render();
    }

    async loadFromDirectory(dirHandle: FileSystemDirectoryHandle): Promise<void> {
        if (!this.container) return;

        try {
            // Scan for area files
            this.index = await scanAreaFiles(dirHandle);

            if (this.index.gameNames.length === 0) {
                this.showMessage('No area scan files found (TrRAt_*_area_scan_*.tsv)');
                return;
            }

            // Populate game selector
            this.populateGameSelector();

            // Try to restore saved state from URL
            if (this.savedState?.game && this.index.gameNames.includes(this.savedState.game)) {
                this.selectedGame = this.savedState.game;
                if (this.gameSelect) this.gameSelect.value = this.selectedGame;
                this.onGameChange(true); // Skip URL write on restore

                // Restore region and city after game is loaded
                if (this.savedState.areaRegion !== null && this.regionSelect) {
                    this.selectedRegion = this.savedState.areaRegion || null;
                    this.regionSelect.value = this.savedState.areaRegion || '';
                }
                if (this.savedState.city !== null && this.citySelect) {
                    this.selectedCity = this.savedState.city || null;
                    this.citySelect.value = this.savedState.city || '';
                }
                this.savedState = null; // Clear after restore
                return;
            }

            // Auto-select first game if only one
            if (this.index.gameNames.length === 1) {
                this.selectedGame = this.index.gameNames[0];
                if (this.gameSelect) this.gameSelect.value = this.selectedGame;
                this.onGameChange();
            }
        } catch (error) {
            const msg = error instanceof Error ? error.message : 'Unknown error';
            this.showMessage(`Failed to scan area files: ${msg}`, true);
        }
    }

    private render(): void {
        if (!this.container) return;

        this.container.innerHTML = '';

        // Controls container
        this.controlsContainer = document.createElement('div');
        this.controlsContainer.className = 'tab-controls';
        this.controlsContainer.innerHTML = `
      <div class="control-group">
        <label for="area-game">Game:</label>
        <select id="area-game" disabled>
          <option value="">Select folder first</option>
        </select>
      </div>
      <div class="control-group">
        <label for="area-region">Region:</label>
        <select id="area-region" disabled>
          <option value="">Select game first</option>
        </select>
      </div>
      <div class="control-group">
        <label for="area-city">City:</label>
        <select id="area-city" disabled>
          <option value="">Select game first</option>
        </select>
      </div>
    `;
        this.container.appendChild(this.controlsContainer);

        // Get select elements
        this.gameSelect = this.controlsContainer.querySelector('#area-game');
        this.regionSelect = this.controlsContainer.querySelector('#area-region');
        this.citySelect = this.controlsContainer.querySelector('#area-city');

        // Add event listeners
        this.gameSelect?.addEventListener('change', () => this.onGameChange());
        this.regionSelect?.addEventListener('change', () => this.onRegionChange());
        this.citySelect?.addEventListener('change', () => this.onCityChange());

        // Info container
        this.infoContainer = document.createElement('div');
        this.infoContainer.className = 'controls';
        this.infoContainer.style.display = 'none';
        this.container.appendChild(this.infoContainer);

        // Canvas container
        this.canvasContainer = document.createElement('div');
        this.canvasContainer.className = 'canvas-container';
        this.container.appendChild(this.canvasContainer);

        // Show placeholder
        this.showMessage('Select a log folder to load area scan files');
    }

    private populateGameSelector(): void {
        if (!this.gameSelect || !this.index) return;

        this.gameSelect.innerHTML = '<option value="">-- Select Game --</option>';
        for (const gameName of this.index.gameNames) {
            const option = document.createElement('option');
            option.value = gameName;
            option.textContent = gameName.replace(/_/g, ' ');
            this.gameSelect.appendChild(option);
        }
        this.gameSelect.disabled = false;
    }

    private onGameChange(skipURLWrite: boolean = false): void {
        if (!this.gameSelect || !this.index) return;

        this.selectedGame = this.gameSelect.value || null;
        this.selectedRegion = null;
        this.selectedCity = null;

        if (!this.selectedGame) {
            this.resetRegionSelector();
            this.resetCitySelector();
            this.clearCanvas();
            if (!skipURLWrite) {
                writeStateToURL({ game: null, areaRegion: null, city: null });
            }
            return;
        }

        // Populate region selector
        const regions = getRegionsForGame(this.index, this.selectedGame);
        this.populateRegionSelector(regions);

        // Populate city selector with all cities
        this.populateCitySelector(skipURLWrite);

        if (!skipURLWrite) {
            writeStateToURL({ game: this.selectedGame, areaRegion: null, city: null });
        }
    }

    private populateRegionSelector(regions: string[]): void {
        if (!this.regionSelect) return;

        this.regionSelect.innerHTML = '<option value="">All Regions</option>';
        for (const region of regions) {
            const option = document.createElement('option');
            option.value = region;
            option.textContent = REGIONS[region] ?? region;
            this.regionSelect.appendChild(option);
        }
        this.regionSelect.disabled = false;
    }

    private resetRegionSelector(): void {
        if (!this.regionSelect) return;
        this.regionSelect.innerHTML = '<option value="">Select game first</option>';
        this.regionSelect.disabled = true;
    }

    private onRegionChange(): void {
        if (!this.regionSelect) return;

        this.selectedRegion = this.regionSelect.value || null;
        this.selectedCity = null;

        // Repopulate city selector based on region
        this.populateCitySelector();

        writeStateToURL({
            areaRegion: this.selectedRegion,
            city: null
        });
    }

    private populateCitySelector(skipURLWrite: boolean = false): void {
        if (!this.citySelect || !this.index || !this.selectedGame) return;

        const cities = getCitiesForGameAndRegion(this.index, this.selectedGame, this.selectedRegion);

        this.citySelect.innerHTML = '<option value="">All Cities</option>';
        for (const city of cities) {
            const option = document.createElement('option');
            option.value = city.fileName;
            option.textContent = getCityDisplayName(city);
            this.citySelect.appendChild(option);
        }
        this.citySelect.disabled = false;

        // Auto-load visualization
        this.loadVisualization(skipURLWrite);
    }

    private resetCitySelector(): void {
        if (!this.citySelect) return;
        this.citySelect.innerHTML = '<option value="">Select game first</option>';
        this.citySelect.disabled = true;
    }

    private onCityChange(): void {
        if (!this.citySelect) return;
        this.selectedCity = this.citySelect.value || null;
        this.loadVisualization();
        writeStateToURL({ city: this.selectedCity });
    }

    private async loadVisualization(_skipURLWrite: boolean = false): Promise<void> {
        if (!this.index || !this.selectedGame) return;

        const cities = getCitiesForGameAndRegion(this.index, this.selectedGame, this.selectedRegion);

        if (cities.length === 0) {
            this.showMessage('No cities found for selection');
            return;
        }

        try {
            if (this.selectedCity) {
                // Load single city
                const city = cities.find(c => c.fileName === this.selectedCity);
                if (city) {
                    this.data = await loadCoordinates(city.handle, getCityDisplayName(city));
                }
            } else {
                // Load all cities in selection
                const files = cities.map(c => ({
                    handle: c.handle,
                    label: getCityDisplayName(c),
                }));
                this.data = await loadMultipleCoordinates(files);
            }

            if (!this.data || this.data.points.length === 0) {
                this.showMessage('No valid coordinates found');
                return;
            }

            this.renderCanvas();
        } catch (error) {
            const msg = error instanceof Error ? error.message : 'Unknown error';
            this.showMessage(`Failed to load coordinates: ${msg}`, true);
        }
    }

    private renderCanvas(): void {
        if (!this.canvasContainer || !this.data || !this.infoContainer) return;

        // Update info
        const cityCount = new Set(this.data.points.map(p => p.cityLabel).filter(Boolean)).size;
        this.infoContainer.innerHTML = `
      <span>Points: ${this.data.points.length}</span>
      ${cityCount > 1 ? `<span>Cities: ${cityCount}</span>` : ''}
      <span>Bounds: X=[${this.data.bounds.minX}, ${this.data.bounds.maxX}], Y=[${this.data.bounds.minY}, ${this.data.bounds.maxY}]</span>
      <span>Size: ${this.data.bounds.width} x ${this.data.bounds.height}</span>
    `;
        this.infoContainer.style.display = 'flex';

        // Create or update canvas
        if (!this.canvas) {
            this.canvasContainer.innerHTML = '';
            this.canvas = createCoordinateCanvas(this.options);
            this.canvas.mount(this.canvasContainer);
        }

        this.canvas.setPoints(this.data.points);
    }

    private clearCanvas(): void {
        this.canvas?.destroy();
        this.canvas = null;
        this.data = null;
        if (this.infoContainer) {
            this.infoContainer.style.display = 'none';
        }
        this.showMessage('Select a game to visualize');
    }

    private showMessage(message: string, isError: boolean = false): void {
        if (!this.canvasContainer) return;

        this.canvas?.destroy();
        this.canvas = null;

        this.canvasContainer.innerHTML = `<div class="${isError ? 'error' : 'tab-placeholder'}">${message}</div>`;
    }

    resetView(): void {
        this.canvas?.resetView();
    }

    /**
     * Restore state from URL (called by main.ts on browser back/forward)
     */
    restoreState(state: Pick<AppState, 'game' | 'areaRegion' | 'city'>): void {
        // If index not loaded yet, save state for later
        if (!this.index) {
            this.savedState = state;
            return;
        }

        // Apply state to UI controls and load visualization
        if (state.game && this.index.gameNames.includes(state.game)) {
            this.selectedGame = state.game;
            if (this.gameSelect) this.gameSelect.value = state.game;
            this.onGameChange(true); // Skip URL write

            // Restore region
            if (state.areaRegion !== null && this.regionSelect) {
                this.selectedRegion = state.areaRegion || null;
                this.regionSelect.value = state.areaRegion || '';
                this.populateCitySelector(true);
            }

            // Restore city
            if (state.city !== null && this.citySelect) {
                this.selectedCity = state.city || null;
                this.citySelect.value = state.city || '';
                this.loadVisualization(true);
            }
        }
    }

    destroy(): void {
        this.canvas?.destroy();
        this.canvas = null;
        this.canvasContainer = null;
        this.controlsContainer = null;
        this.infoContainer = null;
        this.container = null;
        this.data = null;
        this.index = null;
    }
}
