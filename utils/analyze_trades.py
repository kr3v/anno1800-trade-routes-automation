#!/usr/bin/env python3
"""
Analyze trade routes from JSON log file.
Provides high-level overview of trades per city.
"""

import json
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


# ANSI color codes
class Colors:
    RED = '\033[91m'
    GREEN = '\033[92m'
    RESET = '\033[0m'


def load_goods_names(texts_file):
    """Load good names from texts.json."""
    with open(texts_file, 'r', encoding='utf-8') as f:
        return json.load(f)


def parse_timestamp(ts_str):
    """Parse ISO timestamp string to datetime."""
    return datetime.fromisoformat(ts_str.replace('Z', '+00:00'))


def analyze_trades(trades_file, texts_file):
    """Analyze trades and print overview per city."""
    # Load goods names mapping
    goods_names = load_goods_names(texts_file)

    # Load trades
    with open(trades_file, 'r', encoding='utf-8') as f:
        trades = json.load(f)

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

    # Print results
    all_cities = set(received.keys()) | set(sent.keys())

    for city in sorted(all_cities):
        print(f"{city}:")

        # Print received goods
        if city in received and received[city]:
            print("  received:")
            for good_name in sorted(received[city].keys()):
                data = received[city][good_name]
                amount = data['amount']
                print(f"    {good_name}: {amount}")

        if city in sent and sent[city]:
            print("  sent:")
            for good_name in sorted(sent[city].keys()):
                data = sent[city][good_name]
                amount = data['amount']
                print(f"    {good_name}: {amount}")

        print()  # Empty line between cities


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

    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    texts_file = repo_root / 'anno-1800' / 'texts.json'

    # trades_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'trade-executor-history.json'
    # analyze_trades(trades_file, texts_file)

    deficit_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'OW' / 'remaining-deficit.json'
    surplus_file = repo_root / 'anno-1800' / 'trade-route-automation' / 'OW' / 'remaining-surplus.json'
    analyze_deficit_surplus(deficit_file, surplus_file, texts_file)

if __name__ == '__main__':
    main()
