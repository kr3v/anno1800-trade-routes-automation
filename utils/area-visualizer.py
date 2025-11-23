import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.ticker import MultipleLocator, AutoLocator
import sys

f = sys.argv[1] if len(sys.argv) > 1 else None
with open(f, 'r') as file:
    points = file.read()
dst = sys.argv[2] if len(sys.argv) > 2 else 'rectangle.png'

warned = False

# Parse points with optional color code and arrow direction
coords = []
point_types = []
arrow_dirs = []
for line in points.strip().split('\n'):
    lineS = line.split(' ')
    if len(lineS) == 1:
        if not warned:
            print("some lines are not parseable: file={} line={}".format(f, line))
            warned = True
        continue
    line = lineS[1]

    parts = line.split(',')
    if len(parts) < 3:
        continue
    x, y = int(parts[0].strip("msg=")), int(parts[1])
    point_type = parts[2].strip() if len(parts) > 2 else None
    arrow_dir = parts[3].strip() if len(parts) > 3 else None
    coords.append((x, y))
    point_types.append(point_type)
    arrow_dirs.append(arrow_dir)

# Find bounding rectangle
x_coords = [p[0] for p in coords]
y_coords = [p[1] for p in coords]

min_x = min(x_coords)
max_x = max(x_coords)
min_y = min(y_coords)
max_y = max(y_coords)

# Create plot
fig, ax = plt.subplots(figsize=(8, 8))

# Draw rectangle
rect = patches.Rectangle((min_x, min_y), max_x - min_x, max_y - min_y,
                         linewidth=2, edgecolor='blue', facecolor='lightblue', alpha=0.3)
ax.add_patch(rect)

# Define colors for each point type
color_map = {
    'S': 'red',
    'W': 'lightblue',
    'w': 'blue',
    'L': 'lightgreen',
    'Y': 'yellow',
    'N': 'black',
    None: 'red'  # default color for points without type
}

# Define arrow direction vectors (arrow shows arrival direction)
# Arrow starts 10 pixels away and points to 5 pixels away from point
arrow_start_dist = 10
arrow_end_dist = 5
arrow_vectors = {
    'L': ((arrow_start_dist, 1), (0, 1)),   # Coming from left
    'R': ((-arrow_start_dist, -1), (0, -1)),    # Coming from right
    'U': ((-1, -arrow_start_dist), (-1, 0)),   # Coming from up
    'D': ((1, arrow_start_dist), (1, 0)),    # Coming from down
}

# Plot points with arrows
for (x, y), point_type, arrow_dir in zip(coords, point_types, arrow_dirs):
    color = color_map.get(point_type, 'red')

    # Plot the point
    ax.scatter(x, y, color=color, s=25, zorder=5)

    # Add arrow if direction specified
    if arrow_dir and arrow_dir in arrow_vectors:
        (start_dx, start_dy), (end_dx, end_dy) = arrow_vectors[arrow_dir]
        # Draw arrow pointing TO the point (showing arrival direction)
        ax.annotate('', xy=(x + end_dx, y + end_dy), xytext=(x + start_dx, y + start_dy),
                   arrowprops=dict(arrowstyle='->', color=color, lw=1),
                   zorder=4)

# Create legend for point types (not including arrows)
legend_elements = []
for point_type, color in color_map.items():
    if point_type and any(pt == point_type for pt in point_types):
        legend_elements.append(plt.scatter([], [], color=color, s=50, label=point_type))
if legend_elements:
    ax.legend(handles=legend_elements)

# Set axis properties
ax.set_xlim(min_x - 50, max_x + 50)
ax.set_ylim(min_y - 50, max_y + 50)
ax.set_aspect('equal')

# Set minor ticks every 10 units for the grid
ax.xaxis.set_minor_locator(MultipleLocator(10))
ax.yaxis.set_minor_locator(MultipleLocator(10))

# Set major ticks at larger intervals for readable labels
# Use 50 for ranges < 500, otherwise 100
x_range = max_x - min_x + 100  # +100 for the padding
y_range = max_y - min_y + 100
major_interval = 100 if max(x_range, y_range) > 500 else 50

ax.xaxis.set_major_locator(MultipleLocator(major_interval))
ax.yaxis.set_major_locator(MultipleLocator(major_interval))

# Enable grid on minor ticks (10px intervals)
ax.grid(True, which='minor', alpha=0.3)
ax.grid(True, which='major', alpha=0.5, linewidth=0.8)
ax.set_xlabel('X')
ax.set_ylabel('Y')
ax.set_title('Bounding Rectangle with Arrows')

plt.tight_layout()
plt.savefig(dst, dpi=300, bbox_inches='tight')
print(f"Rectangle bounds: X=[{min_x}, {max_x}], Y=[{min_y}, {max_y}]")
print(f"Width={max_x - min_x}, Height={max_y - min_y}")
print("Image saved to {}".format(dst))
