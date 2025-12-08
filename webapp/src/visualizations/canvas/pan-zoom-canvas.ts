/**
 * Interactive canvas with pan and zoom for coordinate visualization
 */

import type { CoordinatePoint } from '@/parsers/coordinates';
import { DEFAULT_POINT_COLORS, getArrowVector } from '@/parsers/coordinates';
import type { ICoordinateCanvas, CoordinateCanvasOptions } from './types';

const DEFAULT_OPTIONS: Required<CoordinateCanvasOptions> = {
  colors: DEFAULT_POINT_COLORS,
  minorGridInterval: 10,
  majorGridInterval: 100,
  showCoordinatesOnHover: true,
  enablePanZoom: true,
  pointRadius: 5,
  arrowSize: 15,
  padding: 50,
};

export class PanZoomCanvas implements ICoordinateCanvas {
  private container: HTMLElement | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private infoElement: HTMLElement | null = null;

  private options: Required<CoordinateCanvasOptions> = { ...DEFAULT_OPTIONS };
  private points: CoordinatePoint[] = [];

  // View state
  private scale: number = 1;
  private offsetX: number = 0;
  private offsetY: number = 0;

  // Bounds
  private bounds = { minX: 0, maxX: 0, minY: 0, maxY: 0 };

  // Interaction state
  private isDragging: boolean = false;
  private lastMouseX: number = 0;
  private lastMouseY: number = 0;

  // Bound event handlers
  private handleMouseDown = this.onMouseDown.bind(this);
  private handleMouseMove = this.onMouseMove.bind(this);
  private handleMouseUp = this.onMouseUp.bind(this);
  private handleWheel = this.onWheel.bind(this);
  private handleResize = this.onResize.bind(this);

  mount(container: HTMLElement): void {
    this.container = container;

    // Create canvas
    this.canvas = document.createElement('canvas');
    this.canvas.style.display = 'block';
    this.ctx = this.canvas.getContext('2d');

    // Create info overlay
    this.infoElement = document.createElement('div');
    this.infoElement.className = 'canvas-info';
    this.infoElement.textContent = 'Pan: drag | Zoom: scroll | Reset: double-click';

    // Set up container
    container.innerHTML = '';
    container.style.position = 'relative';
    container.appendChild(this.canvas);
    container.appendChild(this.infoElement);

    // Add event listeners
    this.canvas.addEventListener('mousedown', this.handleMouseDown);
    this.canvas.addEventListener('mousemove', this.handleMouseMove);
    this.canvas.addEventListener('mouseup', this.handleMouseUp);
    this.canvas.addEventListener('mouseleave', this.handleMouseUp);
    this.canvas.addEventListener('wheel', this.handleWheel, { passive: false });
    this.canvas.addEventListener('dblclick', () => this.resetView());
    window.addEventListener('resize', this.handleResize);

    this.onResize();
  }

  setPoints(points: CoordinatePoint[]): void {
    this.points = points;
    this.calculateBounds();
    this.resetView();
  }

  configure(options: Partial<CoordinateCanvasOptions>): void {
    this.options = { ...this.options, ...options };
    this.render();
  }

  resetView(): void {
    if (!this.canvas) return;

    const width = this.canvas.width;
    const height = this.canvas.height;
    const padding = this.options.padding;

    const dataWidth = this.bounds.maxX - this.bounds.minX;
    const dataHeight = this.bounds.maxY - this.bounds.minY;

    if (dataWidth === 0 || dataHeight === 0) {
      this.scale = 1;
      this.offsetX = width / 2;
      this.offsetY = height / 2;
    } else {
      // Calculate scale to fit with padding
      const scaleX = (width - 2 * padding) / dataWidth;
      const scaleY = (height - 2 * padding) / dataHeight;
      this.scale = Math.min(scaleX, scaleY);

      // Center the view
      const centerX = (this.bounds.minX + this.bounds.maxX) / 2;
      const centerY = (this.bounds.minY + this.bounds.maxY) / 2;
      this.offsetX = width / 2 - centerX * this.scale;
      this.offsetY = height / 2 - centerY * this.scale;
    }

    this.render();
  }

  destroy(): void {
    if (this.canvas) {
      this.canvas.removeEventListener('mousedown', this.handleMouseDown);
      this.canvas.removeEventListener('mousemove', this.handleMouseMove);
      this.canvas.removeEventListener('mouseup', this.handleMouseUp);
      this.canvas.removeEventListener('mouseleave', this.handleMouseUp);
      this.canvas.removeEventListener('wheel', this.handleWheel);
    }
    window.removeEventListener('resize', this.handleResize);

    this.canvas = null;
    this.ctx = null;
    this.infoElement = null;
    this.container = null;
  }

  private calculateBounds(): void {
    if (this.points.length === 0) {
      this.bounds = { minX: 0, maxX: 100, minY: 0, maxY: 100 };
      return;
    }

    const xs = this.points.map(p => p.x);
    const ys = this.points.map(p => p.y);

    this.bounds = {
      minX: Math.min(...xs),
      maxX: Math.max(...xs),
      minY: Math.min(...ys),
      maxY: Math.max(...ys),
    };
  }

  /** Convert data X to screen X */
  private toScreenX(dataX: number): number {
    return dataX * this.scale + this.offsetX;
  }

  /** Convert data Y to screen Y (inverted - Y increases upward in data space) */
  private toScreenY(dataY: number): number {
    if (!this.canvas) return 0;
    // Flip Y: subtract from canvas height
    return this.canvas.height - (dataY * this.scale + this.offsetY);
  }

  /** Convert screen X to data X */
  private toDataX(screenX: number): number {
    return (screenX - this.offsetX) / this.scale;
  }

  /** Convert screen Y to data Y (inverted) */
  private toDataY(screenY: number): number {
    if (!this.canvas) return 0;
    return (this.canvas.height - screenY - this.offsetY) / this.scale;
  }

  private onResize(): void {
    if (!this.canvas || !this.container) return;

    const rect = this.container.getBoundingClientRect();
    this.canvas.width = rect.width;
    this.canvas.height = rect.height;
    this.render();
  }

  private onMouseDown(e: MouseEvent): void {
    if (!this.options.enablePanZoom) return;
    this.isDragging = true;
    this.lastMouseX = e.clientX;
    this.lastMouseY = e.clientY;
    if (this.canvas) this.canvas.style.cursor = 'grabbing';
  }

  private onMouseMove(e: MouseEvent): void {
    if (!this.canvas) return;

    if (this.isDragging && this.options.enablePanZoom) {
      const dx = e.clientX - this.lastMouseX;
      const dy = e.clientY - this.lastMouseY;
      this.offsetX += dx;
      this.offsetY += dy;
      this.lastMouseX = e.clientX;
      this.lastMouseY = e.clientY;
      this.render();
    } else if (this.options.showCoordinatesOnHover) {
      // Update info with coordinates under cursor
      const rect = this.canvas.getBoundingClientRect();
      const screenX = e.clientX - rect.left;
      const screenY = e.clientY - rect.top;

      // Convert screen to data coordinates
      const dataX = this.toDataX(screenX);
      const dataY = this.toDataY(screenY);

      // Find nearest point
      const nearest = this.findNearestPoint(dataX, dataY);
      const nearestInfo = nearest
        ? ` | Nearest: (${nearest.x}, ${nearest.y})${nearest.type ? ` [${nearest.type}]` : ''}`
        : '';

      if (this.infoElement) {
        this.infoElement.textContent =
          `(${Math.round(dataX)}, ${Math.round(dataY)})${nearestInfo} | Zoom: ${(this.scale * 100).toFixed(0)}%`;
      }
    }
  }

  private onMouseUp(): void {
    this.isDragging = false;
    if (this.canvas) this.canvas.style.cursor = 'grab';
  }

  private onWheel(e: WheelEvent): void {
    if (!this.options.enablePanZoom || !this.canvas) return;
    e.preventDefault();

    const rect = this.canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;

    // Zoom factor
    const zoomFactor = e.deltaY < 0 ? 1.1 : 0.9;
    const newScale = this.scale * zoomFactor;

    // Clamp scale
    if (newScale < 0.1 || newScale > 50) return;

    // Adjust offset to zoom toward mouse position
    this.offsetX = mouseX - (mouseX - this.offsetX) * zoomFactor;
    this.offsetY = mouseY - (mouseY - this.offsetY) * zoomFactor;
    this.scale = newScale;

    this.render();
  }

  private findNearestPoint(dataX: number, dataY: number): CoordinatePoint | null {
    let nearest: CoordinatePoint | null = null;
    let minDist = Infinity;

    for (const point of this.points) {
      const dist = Math.hypot(point.x - dataX, point.y - dataY);
      if (dist < minDist && dist < 50 / this.scale) {
        minDist = dist;
        nearest = point;
      }
    }

    return nearest;
  }

  private render(): void {
    if (!this.ctx || !this.canvas) return;

    const ctx = this.ctx;
    const width = this.canvas.width;
    const height = this.canvas.height;

    // Clear
    ctx.fillStyle = '#1a1a2e';
    ctx.fillRect(0, 0, width, height);

    // Draw grid
    this.drawGrid();

    // Draw bounding rectangle
    this.drawBoundingRect();

    // Draw points and arrows
    this.drawPoints();

    // Draw city labels (on top of points)
    this.drawCityLabels();

    // Draw legend (on top of everything)
    this.drawLegend();
  }

  private drawGrid(): void {
    if (!this.ctx || !this.canvas) return;

    const ctx = this.ctx;
    const width = this.canvas.width;
    const height = this.canvas.height;

    // Calculate visible data range (accounting for inverted Y)
    const minDataX = this.toDataX(0);
    const maxDataX = this.toDataX(width);
    const minDataY = this.toDataY(height); // bottom of screen = min Y
    const maxDataY = this.toDataY(0);      // top of screen = max Y

    // Minor grid
    const minorInterval = this.options.minorGridInterval;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    ctx.lineWidth = 1;

    const startMinorX = Math.floor(minDataX / minorInterval) * minorInterval;
    const startMinorY = Math.floor(minDataY / minorInterval) * minorInterval;

    ctx.beginPath();
    for (let x = startMinorX; x <= maxDataX; x += minorInterval) {
      const screenX = this.toScreenX(x);
      ctx.moveTo(screenX, 0);
      ctx.lineTo(screenX, height);
    }
    for (let y = startMinorY; y <= maxDataY; y += minorInterval) {
      const screenY = this.toScreenY(y);
      ctx.moveTo(0, screenY);
      ctx.lineTo(width, screenY);
    }
    ctx.stroke();

    // Major grid
    const majorInterval = this.options.majorGridInterval;
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 1;

    const startMajorX = Math.floor(minDataX / majorInterval) * majorInterval;
    const startMajorY = Math.floor(minDataY / majorInterval) * majorInterval;

    ctx.beginPath();
    for (let x = startMajorX; x <= maxDataX; x += majorInterval) {
      const screenX = this.toScreenX(x);
      ctx.moveTo(screenX, 0);
      ctx.lineTo(screenX, height);
    }
    for (let y = startMajorY; y <= maxDataY; y += majorInterval) {
      const screenY = this.toScreenY(y);
      ctx.moveTo(0, screenY);
      ctx.lineTo(width, screenY);
    }
    ctx.stroke();

    // Axis labels
    ctx.fillStyle = '#a0a0a0';
    ctx.font = '10px monospace';
    ctx.textAlign = 'center';

    // X axis labels at bottom
    for (let x = startMajorX; x <= maxDataX; x += majorInterval) {
      const screenX = this.toScreenX(x);
      ctx.fillText(String(x), screenX, height - 5);
    }

    // Y axis labels on left (now showing correct inverted values)
    ctx.textAlign = 'left';
    for (let y = startMajorY; y <= maxDataY; y += majorInterval) {
      const screenY = this.toScreenY(y);
      ctx.fillText(String(y), 5, screenY + 3);
    }
  }

  private drawBoundingRect(): void {
    if (!this.ctx || this.points.length === 0) return;

    const ctx = this.ctx;
    const { minX, minY, maxX, maxY } = this.bounds;

    const screenMinX = this.toScreenX(minX);
    const screenMaxY = this.toScreenY(minY); // minY in data = bottom in screen (larger Y)
    const screenMaxX = this.toScreenX(maxX);
    const screenMinY = this.toScreenY(maxY); // maxY in data = top in screen (smaller Y)

    const screenWidth = screenMaxX - screenMinX;
    const screenHeight = screenMaxY - screenMinY;

    ctx.strokeStyle = '#4a9eff';
    ctx.lineWidth = 2;
    ctx.fillStyle = 'rgba(74, 158, 255, 0.1)';

    ctx.beginPath();
    ctx.rect(screenMinX, screenMinY, screenWidth, screenHeight);
    ctx.fill();
    ctx.stroke();
  }

  private drawPoints(): void {
    if (!this.ctx) return;

    const ctx = this.ctx;
    const colors = this.options.colors;
    const radius = this.options.pointRadius;
    const arrowSize = this.options.arrowSize;

    for (const point of this.points) {
      const screenX = this.toScreenX(point.x);
      const screenY = this.toScreenY(point.y);
      const color = colors[point.type ?? 'default'] ?? colors['default'];

      // Draw arrow if direction specified
      if (point.arrowDir) {
        const arrow = getArrowVector(point.arrowDir, arrowSize, arrowSize / 3);
        if (arrow) {
          const [startDx, startDy, endDx, endDy] = arrow;
          // Note: arrow Y directions are inverted for screen space
          this.drawArrow(
            ctx,
            screenX + startDx * this.scale,
            screenY - startDy * this.scale, // invert Y
            screenX + endDx * this.scale,
            screenY - endDy * this.scale,   // invert Y
            color
          );
        }
      }

      // Draw point
      ctx.beginPath();
      ctx.arc(screenX, screenY, radius, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();
    }
  }

  private drawArrow(
    ctx: CanvasRenderingContext2D,
    fromX: number,
    fromY: number,
    toX: number,
    toY: number,
    color: string
  ): void {
    const headLen = 8;
    const angle = Math.atan2(toY - fromY, toX - fromX);

    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(fromX, fromY);
    ctx.lineTo(toX, toY);
    ctx.stroke();

    // Arrow head
    ctx.beginPath();
    ctx.moveTo(toX, toY);
    ctx.lineTo(
      toX - headLen * Math.cos(angle - Math.PI / 6),
      toY - headLen * Math.sin(angle - Math.PI / 6)
    );
    ctx.lineTo(
      toX - headLen * Math.cos(angle + Math.PI / 6),
      toY - headLen * Math.sin(angle + Math.PI / 6)
    );
    ctx.closePath();
    ctx.fillStyle = color;
    ctx.fill();
  }

  private drawLegend(): void {
    if (!this.ctx || !this.canvas) return;

    const ctx = this.ctx;
    const colors = this.options.colors;

    // Collect unique point types present in data
    const presentTypes = new Set<string>();
    for (const point of this.points) {
      if (point.type) presentTypes.add(point.type);
    }

    if (presentTypes.size === 0) return;

    // Legend labels
    const typeLabels: Record<string, string> = {
      'S': 'occupied',
      'W': 'water',
      'w': 'load/unload for ships',
      'L': 'land',
      'Y': '?',
      'N': 'not accessible',
    };

    const items = [...presentTypes].sort().map(type => ({
      type,
      label: typeLabels[type] ?? type,
      color: colors[type] ?? colors['default'],
    }));

    // Calculate legend dimensions
    const padding = 8;
    const itemHeight = 18;
    const circleRadius = 5;
    const legendHeight = items.length * itemHeight + padding * 2;
    const legendWidth = 120;

    // Position in top-right corner
    const x = this.canvas.width - legendWidth - 10;
    const y = 10;

    // Draw background
    ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.roundRect(x, y, legendWidth, legendHeight, 4);
    ctx.fill();
    ctx.stroke();

    // Draw items
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';

    items.forEach((item, i) => {
      const itemY = y + padding + i * itemHeight + itemHeight / 2;

      // Draw circle
      ctx.beginPath();
      ctx.arc(x + padding + circleRadius, itemY, circleRadius, 0, Math.PI * 2);
      ctx.fillStyle = item.color;
      ctx.fill();
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.5)';
      ctx.lineWidth = 1;
      ctx.stroke();

      // Draw label
      ctx.fillStyle = '#eaeaea';
      ctx.fillText(item.label, x + padding + circleRadius * 2 + 8, itemY);
    });
  }

  private drawCityLabels(): void {
    if (!this.ctx || !this.canvas) return;

    // Group points by city label
    const cityCenters = new Map<string, { sumX: number; sumY: number; count: number }>();

    for (const point of this.points) {
      if (!point.cityLabel) continue;

      if (!cityCenters.has(point.cityLabel)) {
        cityCenters.set(point.cityLabel, { sumX: 0, sumY: 0, count: 0 });
      }

      const center = cityCenters.get(point.cityLabel)!;
      center.sumX += point.x;
      center.sumY += point.y;
      center.count++;
    }

    if (cityCenters.size <= 1) return; // Don't show label for single city

    const ctx = this.ctx;
    ctx.font = 'bold 12px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    for (const [label, center] of cityCenters) {
      // Calculate centroid
      const dataX = center.sumX / center.count;
      const dataY = center.sumY / center.count;

      // Convert to screen coordinates
      const screenX = this.toScreenX(dataX);
      const screenY = this.toScreenY(dataY);

      // Draw label with background
      const textWidth = ctx.measureText(label).width;
      const padding = 4;

      ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
      ctx.beginPath();
      ctx.roundRect(
        screenX - textWidth / 2 - padding,
        screenY - 8 - padding,
        textWidth + padding * 2,
        16 + padding * 2,
        3
      );
      ctx.fill();

      ctx.fillStyle = '#ffffff';
      ctx.fillText(label, screenX, screenY);
    }
  }
}
