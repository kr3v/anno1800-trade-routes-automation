/**
 * Chart.js implementation of ILineChart
 */

import {
  Chart,
  ChartConfiguration,
  ChartData,
  ChartOptions,
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Title,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import 'chart.js/auto';
import zoomPlugin from 'chartjs-plugin-zoom';
import type { ILineChart, LineChartOptions, SeriesConfig } from '../../types';

// Register Chart.js components
Chart.register(
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  TimeScale,
  Title,
  Tooltip,
  Legend,
  Filler,
  zoomPlugin
);

export class ChartJSLineChart implements ILineChart {
  private chart: Chart | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private options: LineChartOptions = {};
  private series: SeriesConfig[] = [];

  mount(container: HTMLElement): void {
    this.canvas = document.createElement('canvas');
    container.innerHTML = '';
    container.appendChild(this.canvas);
    this.createChart();
  }

  setSeries(series: SeriesConfig[]): void {
    this.series = series;
    this.updateChart();
  }

  configure(options: LineChartOptions): void {
    this.options = { ...this.options, ...options };
    this.updateChart();
  }

  resize(): void {
    this.chart?.resize();
  }

  resetZoom(): void {
    this.chart?.resetZoom();
  }

  destroy(): void {
    this.chart?.destroy();
    this.chart = null;
    this.canvas = null;
  }

  private createChart(): void {
    if (!this.canvas) return;

    const config = this.buildConfig();
    this.chart = new Chart(this.canvas, config);
  }

  private updateChart(): void {
    if (!this.chart) {
      this.createChart();
      return;
    }

    const config = this.buildConfig();
    this.chart.data = config.data;
    this.chart.options = config.options as ChartOptions<'line'>;
    this.chart.update();
  }

  private buildConfig(): ChartConfiguration<'line'> {
    const data: ChartData<'line'> = {
      datasets: this.series.map(s => ({
        label: s.label,
        data: s.data.map(p => ({ x: p.timestamp.getTime(), y: p.value })),
        borderColor: s.color,
        backgroundColor: s.color + '20',
        borderWidth: s.lineWidth ?? 2,
        borderDash: s.lineStyle === 'dashed' ? [5, 5] : undefined,
        pointRadius: s.showPoints === false ? 0 : (s.pointSize ?? 3),
        pointHoverRadius: (s.pointSize ?? 3) + 2,
        tension: 0.1,
        fill: false,
      })),
    };

    const options: ChartOptions<'line'> = {
      responsive: this.options.responsive ?? true,
      maintainAspectRatio: this.options.aspectRatio !== undefined,
      aspectRatio: this.options.aspectRatio,
      interaction: {
        mode: 'index',
        intersect: false,
      },
      plugins: {
        title: {
          display: !!this.options.title,
          text: this.options.title ?? '',
          color: '#eaeaea',
          font: { size: 14, weight: 'bold' },
        },
        legend: {
          display: this.options.showLegend ?? true,
          position: this.options.legendPosition ?? 'top',
          labels: { color: '#eaeaea' },
        },
        tooltip: {
          backgroundColor: 'rgba(0, 0, 0, 0.8)',
          titleColor: '#eaeaea',
          bodyColor: '#eaeaea',
          callbacks: {
            title: (items) => {
              if (items.length === 0) return '';
              const x = items[0].parsed.x;
              if (x === null || x === undefined) return '';
              const date = new Date(x);
              return date.toLocaleTimeString();
            },
          },
        },
        zoom: {
          pan: {
            enabled: true,
            mode: 'x',
          },
          zoom: {
            wheel: {
              enabled: true,
            },
            pinch: {
              enabled: true,
            },
            mode: 'x',
          },
        },
      },
      scales: {
        x: {
          type: 'linear',
          title: {
            display: !!this.options.xAxisLabel,
            text: this.options.xAxisLabel ?? '',
            color: '#a0a0a0',
          },
          ticks: {
            color: '#a0a0a0',
            callback: (value) => {
              const date = new Date(value as number);
              return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            },
          },
          grid: {
            display: this.options.showGrid ?? true,
            color: 'rgba(255, 255, 255, 0.1)',
          },
        },
        y: {
          type: 'linear',
          position: 'left',
          title: {
            display: !!this.options.yAxisLabel,
            text: this.options.yAxisLabel ?? '',
            color: '#a0a0a0',
          },
          ticks: { color: '#a0a0a0' },
          grid: {
            display: this.options.showGrid ?? true,
            color: 'rgba(255, 255, 255, 0.1)',
          },
        },
      },
    };

    // Add right Y axis if requested
    if (this.options.yAxisBothSides && options.scales) {
      options.scales.y2 = {
        type: 'linear',
        position: 'right',
        ticks: { color: '#a0a0a0' },
        grid: { display: false },
      };
    }

    return { type: 'line', data, options };
  }
}
