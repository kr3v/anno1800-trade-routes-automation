#!/usr/bin/env python3
"""
Analyze trade routes from JSON log file.
Provides high-level overview of trades per city.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path


# ANSI color codes
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    BOLD_RED = '\033[91m\033[1m'
    BOLD_GREEN = '\033[92m\033[1m'
    RESET = '\033[0m'


def load_goods_names(texts_file):
    """Load good names from texts.json."""
    with open(texts_file, 'r', encoding='utf-8') as f:
        return json.load(f)


def parse_timestamp(ts_str):
    """Parse ISO timestamp string to datetime.

    Note: The 'Z' in logs represents local timezone, not UTC.
    """
    # Remove 'Z' and parse as naive datetime, then treat as local timezone
    if ts_str.endswith('Z'):
        naive_dt = datetime.fromisoformat(ts_str[:-1])
        # Get local timezone and apply it without conversion
        local_tz = datetime.now().astimezone().tzinfo
        return naive_dt.replace(tzinfo=local_tz)
    return datetime.fromisoformat(ts_str)


def parse_duration(duration_str):
    """
    Parse duration string like '15m', '2h', '1d' into timedelta.
    Returns None if duration_str is None or empty.
    """
    if not duration_str:
        return None

    match = re.match(r'^(\d+)([mhd])$', duration_str.lower())
    if not match:
        raise ValueError(f"Invalid duration format: {duration_str}. Use format like '15m', '2h', or '1d'")

    value, unit = match.groups()
    value = int(value)

    if unit == 'm':
        return timedelta(minutes=value)
    elif unit == 'h':
        return timedelta(hours=value)
    elif unit == 'd':
        return timedelta(days=value)

    raise ValueError(f"Unknown time unit: {unit}")


def get_display_width(text):
    """Get display width of text (excluding ANSI codes)."""
    import re
    # Remove ANSI escape codes
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    clean_text = ansi_escape.sub('', text)
    return len(clean_text)


def format_trade_cell(received_amt, sent_amt, max_value):
    """Format a single cell with ↑received/sent↓ and color coding."""
    parts = []

    if received_amt > 0:
        # Calculate color based on percentage of max
        pct = (received_amt / max_value) if max_value > 0 else 0
        if pct >= 0.75:
            color = Colors.BOLD_GREEN
        elif pct >= 0.25:
            color = Colors.GREEN
        else:
            color = ''

        reset = Colors.RESET if color else ''
        parts.append(f"{color}↑{received_amt}{reset}")

    if sent_amt > 0:
        # Calculate color based on percentage of max
        pct = (sent_amt / max_value) if max_value > 0 else 0
        if pct >= 0.75:
            color = Colors.BOLD_RED
        elif pct >= 0.25:
            color = Colors.RED
        else:
            color = ''

        reset = Colors.RESET if color else ''
        parts.append(f"{color}{sent_amt}↓{reset}")

    if not parts:
        return ""

    return "/".join(parts)


def print_trade_table(received, sent):
    """Print trades in a formatted table with UTF box drawing characters."""
    # Collect all goods and cities
    all_goods = set()
    all_cities = set()

    for city, goods in received.items():
        all_cities.add(city)
        all_goods.update(goods.keys())

    for city, goods in sent.items():
        all_cities.add(city)
        all_goods.update(goods.keys())

    if not all_goods or not all_cities:
        return

    # Separate cities into c* and n* groups
    c_cities = [city for city in all_cities if city.startswith('c')]
    n_cities = [city for city in all_cities if city.startswith('n')]

    # Calculate total volume per city
    city_volumes = {}
    for city in all_cities:
        total_volume = 0
        for good in all_goods:
            recv_amt = received.get(city, {}).get(good, {}).get('amount', 0)
            sent_amt = sent.get(city, {}).get(good, {}).get('amount', 0)
            total_volume += recv_amt + sent_amt
        city_volumes[city] = total_volume

    # Sort each group by total volume (descending), then combine
    c_cities_sorted = sorted(c_cities, key=lambda c: city_volumes[c], reverse=True)
    n_cities_sorted = sorted(n_cities, key=lambda c: city_volumes[c], reverse=True)
    cities_list = c_cities_sorted + n_cities_sorted

    # Calculate total volume per good and find max value for color coding
    good_volumes = {}
    max_value = 0

    for good in all_goods:
        total_volume = 0
        for city in cities_list:
            recv_amt = received.get(city, {}).get(good, {}).get('amount', 0)
            sent_amt = sent.get(city, {}).get(good, {}).get('amount', 0)
            total_volume += recv_amt + sent_amt
            max_value = max(max_value, recv_amt, sent_amt)
        good_volumes[good] = total_volume

    # Sort goods by total volume (descending)
    goods_list = sorted(all_goods, key=lambda g: good_volumes[g], reverse=True)

    # Build table data with formatted cells
    table_data = []
    for good in goods_list:
        row = [good]
        for city in cities_list:
            recv_amt = received.get(city, {}).get(good, {}).get('amount', 0)
            sent_amt = sent.get(city, {}).get(good, {}).get('amount', 0)
            cell = format_trade_cell(recv_amt, sent_amt, max_value)
            row.append(cell)
        # Only include rows that have at least one trade
        if any(row[1:]):
            table_data.append(row)

    if not table_data:
        return

    # Calculate column widths (accounting for ANSI codes)
    col_widths = [len("Good/City")]
    for city in cities_list:
        col_widths.append(len(city))

    for row in table_data:
        for i, cell in enumerate(row):
            width = get_display_width(cell)
            if i < len(col_widths):
                col_widths[i] = max(col_widths[i], width)

    # Print header
    header = ["Good/City"] + cities_list
    header_row = "│ " + " │ ".join(
        header[i].ljust(col_widths[i]) for i in range(len(header))
    ) + " │"

    # Top border
    top_border = "┌─" + "─┬─".join("─" * col_widths[i] for i in range(len(col_widths))) + "─┐"
    print(top_border)

    # Header
    print(header_row)

    # Header separator
    header_sep = "├─" + "─┼─".join("─" * col_widths[i] for i in range(len(col_widths))) + "─┤"
    print(header_sep)

    # Data rows
    for row_idx, row in enumerate(table_data):
        cells = []
        for i, cell in enumerate(row):
            # Pad considering ANSI codes
            display_width = get_display_width(cell)
            padding = col_widths[i] - display_width
            cells.append(cell + " " * padding)

        print("│ " + " │ ".join(cells) + " │")

    # Bottom border
    bottom_border = "└─" + "─┴─".join("─" * col_widths[i] for i in range(len(col_widths))) + "─┘"
    print(bottom_border)


def analyze_trades(trades_file, texts_file, duration=None):
    """Analyze trades and print overview per city."""
    # Load goods names mapping
    goods_names = load_goods_names(texts_file)

    # Load trades
    with open(trades_file, 'r', encoding='utf-8') as f:
        trades = json.load(f)

    # Filter trades by duration if specified
    if duration:
        # Get timezone from first trade if available
        if trades:
            first_start = parse_timestamp(trades[0]['_start'])
            cutoff_time = datetime.now(first_start.tzinfo) - duration
        else:
            cutoff_time = datetime.now() - duration

        original_count = len(trades)
        trades = [t for t in trades if parse_timestamp(t['_start']) >= cutoff_time]
        print(f"Filtered to trades from {cutoff_time} last {duration}: {len(trades)}/{original_count} trades\n")

    # Data structures to collect trade info
    # city -> good_id -> {amount: int, first_time: datetime, last_time: datetime}
    received = defaultdict(lambda: defaultdict(lambda: {'amount': 0, 'first_time': None, 'last_time': None}))
    sent = defaultdict(lambda: defaultdict(lambda: {'amount': 0, 'first_time': None, 'last_time': None}))

    # Process each trade
    for trade in trades:
        good_id = str(trade['good_id'])
        good_name = trade.get('good_name', goods_names.get(good_id, f"Unknown({good_id})"))
        amount = trade['good_amount']

        # Parse timestamps
        start_time = parse_timestamp(trade['_start'])
        end_time = parse_timestamp(trade['_end'])

        # Destination city received goods
        dst_city = trade['area_dst_name']
        dst_data = received[dst_city][good_name]
        dst_data['amount'] += amount
        if dst_data['first_time'] is None or start_time < dst_data['first_time']:
            dst_data['first_time'] = start_time
        if dst_data['last_time'] is None or end_time > dst_data['last_time']:
            dst_data['last_time'] = end_time

        # Source city sent goods
        src_city = trade['area_src_name']
        src_data = sent[src_city][good_name]
        src_data['amount'] += amount
        if src_data['first_time'] is None or start_time < src_data['first_time']:
            src_data['first_time'] = start_time
        if src_data['last_time'] is None or end_time > src_data['last_time']:
            src_data['last_time'] = end_time

    # Print results as table
    print("\nTrade History:")
    print_trade_table(received, sent)
    print()


def sort_by_total_then_name(item):
    """
    Sorting key function for deficit/surplus items.
    Change this function to customize sort order.

    Current: Sort by total (descending), then by name (ascending)
    Alternative examples:
      - Sort by name only: return (item[1]['name'],)
      - Sort by total ascending: return (-item[1]['total'], item[1]['name'])
    """
    good_id, data = item
    return (-data['total'], data['name'])


def analyze_deficit_surplus(deficit_file, surplus_file, texts_file):
    """Analyze and print deficit/surplus data."""
    goods_names = load_goods_names(texts_file)

    # Load deficit and surplus data
    deficit_data = {}
    surplus_data = {}

    if deficit_file.exists():
        with open(deficit_file, 'r', encoding='utf-8') as f:
            raw_deficit = json.load(f)
            for good_id, info in raw_deficit.items():
                deficit_data[good_id] = {
                    'name': goods_names.get(good_id, f"Unknown({good_id})"),
                    'total': info['Total'],
                    'areas': [(area['AreaName'], area['Amount']) for area in info['Areas']]
                }

    if surplus_file.exists():
        with open(surplus_file, 'r', encoding='utf-8') as f:
            raw_surplus = json.load(f)
            for good_id, info in raw_surplus.items():
                surplus_data[good_id] = {
                    'name': goods_names.get(good_id, f"Unknown({good_id})"),
                    'total': info['Total'],
                    'areas': [(area['AreaName'], area['Amount']) for area in info['Areas']]
                }

    # Print deficit
    if deficit_data:
        print("deficit:")
        sorted_deficit = sorted(deficit_data.items(), key=sort_by_total_then_name)
        for good_id, data in sorted_deficit:
            total_colored = f"{Colors.RED}{data['total']}{Colors.RESET}"
            areas_str = ", ".join([f"{area} @{Colors.RED}{amt}{Colors.RESET}"
                                   for area, amt in sorted(data['areas'])])
            print(f"  {data['name']}: {total_colored} ({areas_str})")
        print()

    # Print surplus
    if surplus_data:
        print("surplus:")
        sorted_surplus = sorted(surplus_data.items(), key=sort_by_total_then_name)
        for good_id, data in sorted_surplus:
            total_colored = f"{Colors.GREEN}{data['total']}{Colors.RESET}"
            areas_str = ", ".join([f"{area} @{Colors.GREEN}{amt}{Colors.RESET}"
                                   for area, amt in sorted(data['areas'])])
            print(f"  {data['name']}: {total_colored} ({areas_str})")
        print()


def main():
    # note: the script assumes that `repo_root / 'anno-1800'` is a symlink to `<anno 1800 installation>/lua/` like
    # `anno-1800 -> '/data/games/steam/steamapps/common/Anno 1800/lua/'`

    parser = argparse.ArgumentParser(
        description='Analyze trade routes from JSON log file',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Duration format examples:
  --duration 15m    Show trades from last 15 minutes
  --duration 2h     Show trades from last 2 hours
  --duration 1d     Show trades from last 1 day
  (no flag)         Show all trades (default)
        '''
    )
    parser.add_argument(
        '--duration',
        type=str,
        help="Filter trades from last duration (e.g., '15m', '2h', '1d')"
    )
    args = parser.parse_args()

    # Parse duration if provided
    duration = None
    if args.duration:
        try:
            duration = parse_duration(args.duration)
        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)

    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    texts_file = repo_root / 'anno-1800' / 'texts.json'

    trades_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'trade-executor-history.json'
    analyze_trades(trades_file, texts_file, duration)

    deficit_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'OW' / 'remaining-deficit.json'
    surplus_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'OW' / 'remaining-surplus.json'
    analyze_deficit_surplus(deficit_file, surplus_file, texts_file)

if __name__ == '__main__':
    main()
