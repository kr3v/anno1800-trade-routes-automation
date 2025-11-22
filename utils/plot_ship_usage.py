#!/usr/bin/env python3
"""
Plot ship usage and task spawning from trade execution logs.
Shows 4 lines: ships available (regular/hub) and tasks spawned (regular/hub).
"""

import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict
import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def parse_timestamp(ts_str):
    """Parse ISO timestamp string to datetime (treat Z as local timezone)."""
    if ts_str.endswith('Z'):
        naive_dt = datetime.fromisoformat(ts_str[:-1])
        local_tz = datetime.now().astimezone().tzinfo
        return naive_dt.replace(tzinfo=local_tz)
    return datetime.fromisoformat(ts_str)


def parse_log_file(log_path):
    """Parse a log file and extract ships available and tasks spawned."""
    with open(log_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract timestamp from log content
    timestamp_match = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)', content)
    timestamp = parse_timestamp(timestamp_match.group(1)) if timestamp_match else None

    # Extract ships available
    ships_match = re.search(r'Total available trade route automation ships:\s*(\d+)', content)
    ships_available = int(ships_match.group(1)) if ships_match else None

    # Extract tasks spawned
    tasks_match = re.search(r'Spawned\s+(\d+)\s+async tasks for trade route execution', content)
    tasks_spawned = int(tasks_match.group(1)) if tasks_match else 0

    return {
        'timestamp': timestamp,
        'ships_available': ships_available,
        'tasks_spawned': tasks_spawned,
    }


def moving_average(values, window_size):
    """Calculate moving average with given window size."""
    if len(values) < window_size:
        return values

    result = []
    for i in range(len(values)):
        start = max(0, i - window_size // 2)
        end = min(len(values), i + window_size // 2 + 1)
        result.append(sum(values[start:end]) / (end - start))
    return result


def plot_ship_usage(log_dir, output_file='ship_usage.png', moving_avg_window=10):
    """Generate plot of ship usage over time.

    Args:
        log_dir: Directory containing log files
        output_file: Output PNG filename
        moving_avg_window: Window size for moving average (number of data points)
    """
    log_dir = Path(log_dir)

    # Parse all log files
    regular_logs = []
    hub_logs = []

    for log_file in sorted(log_dir.glob('trade-execute-iteration.*.log*')):
        if log_file.name.endswith('.log.hub'):
            data = parse_log_file(log_file)
            if data['timestamp']:
                hub_logs.append(data)
        elif log_file.name.endswith('.log'):
            data = parse_log_file(log_file)
            if data['timestamp']:
                regular_logs.append(data)

    if not regular_logs and not hub_logs:
        print("No log files found with valid data.")
        return

    # Extract data for plotting
    regular_times = [log['timestamp'] for log in regular_logs]
    regular_ships = [log['ships_available'] for log in regular_logs]
    regular_tasks = [log['tasks_spawned'] for log in regular_logs]

    hub_times = [log['timestamp'] for log in hub_logs]
    hub_ships = [log['ships_available'] for log in hub_logs]
    hub_tasks = [log['tasks_spawned'] for log in hub_logs]

    # Calculate moving averages
    regular_ships_ma = moving_average(regular_ships, moving_avg_window) if regular_ships else []
    regular_tasks_ma = moving_average(regular_tasks, moving_avg_window) if regular_tasks else []
    hub_ships_ma = moving_average(hub_ships, moving_avg_window) if hub_ships else []
    hub_tasks_ma = moving_average(hub_tasks, moving_avg_window) if hub_tasks else []

    # Create plot with wider figure
    fig, ax = plt.subplots(figsize=(24, 8))

    # Plot 4 lines with smaller markers
    if regular_times:
        ax.plot(regular_times, regular_ships, 'o-', label='Ships Available (Regular)',
                color='#2E86AB', linewidth=1, markersize=3, alpha=0.4)
        ax.plot(regular_times, regular_tasks, 's--', label='Tasks Spawned (Regular)',
                color='#A23B72', linewidth=1, markersize=3, alpha=0.4)

        # Plot moving averages with thicker lines
        ax.plot(regular_times, regular_ships_ma, '-', label='Ships Available (Regular) - Trend',
                color='#2E86AB', linewidth=3, alpha=0.9)
        ax.plot(regular_times, regular_tasks_ma, '--', label='Tasks Spawned (Regular) - Trend',
                color='#A23B72', linewidth=3, alpha=0.9)

    if hub_times:
        ax.plot(hub_times, hub_ships, 'o-', label='Ships Available (Hub)',
                color='#06A77D', linewidth=1, markersize=3, alpha=0.4)
        ax.plot(hub_times, hub_tasks, 's--', label='Tasks Spawned (Hub)',
                color='#F18F01', linewidth=1, markersize=3, alpha=0.4)

        # Plot moving averages with thicker lines
        ax.plot(hub_times, hub_ships_ma, '-', label='Ships Available (Hub) - Trend',
                color='#06A77D', linewidth=3, alpha=0.9)
        ax.plot(hub_times, hub_tasks_ma, '--', label='Tasks Spawned (Hub) - Trend',
                color='#F18F01', linewidth=3, alpha=0.9)

    # Format plot
    ax.set_xlabel('Time', fontsize=12, fontweight='bold')
    ax.set_ylabel('Number of Ships/Tasks', fontsize=12, fontweight='bold')
    ax.set_title('Trade Route Automation: Ship Availability & Task Spawning',
                 fontsize=14, fontweight='bold', pad=20)
    ax.legend(loc='best', fontsize=10, framealpha=0.9)
    ax.grid(True, alpha=0.3, linestyle='--')

    # Add Y axis on both sides
    ax.yaxis.set_ticks_position('both')
    ax.tick_params(axis='y', which='both', direction='in', right=True, labelright=True)

    # Format x-axis to show times nicely
    ax.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
    plt.xticks(rotation=45, ha='right')

    # Add some padding
    plt.tight_layout()

    # Save to file with higher DPI for better zoom quality
    plt.savefig(output_file, dpi=200, bbox_inches='tight')
    print(f"Plot saved to: {output_file}")
    print(f"  Moving average window: {moving_avg_window} data points")

    # Print summary statistics
    print("\nSummary:")
    if regular_logs:
        avg_regular_ships = sum(regular_ships) / len(regular_ships)
        avg_regular_tasks = sum(regular_tasks) / len(regular_tasks)
        print(f"  Regular trades: {len(regular_logs)} iterations")
        print(f"    Avg ships available: {avg_regular_ships:.1f}")
        print(f"    Avg tasks spawned: {avg_regular_tasks:.1f}")

    if hub_logs:
        avg_hub_ships = sum(hub_ships) / len(hub_ships)
        avg_hub_tasks = sum(hub_tasks) / len(hub_tasks)
        print(f"  Hub trades: {len(hub_logs)} iterations")
        print(f"    Avg ships available: {avg_hub_ships:.1f}")
        print(f"    Avg tasks spawned: {avg_hub_tasks:.1f}")


def main():
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    log_dir = repo_root / 'anno-1800' / 'trade-route-automation' / 'OW'
    output_file = repo_root / 'ship_usage.png'

    plot_ship_usage(log_dir, output_file)


if __name__ == '__main__':
    main()
