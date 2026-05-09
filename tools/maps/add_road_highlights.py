import json
import geopandas as gpd
import matplotlib.pyplot as plt
from PIL import Image
import os

def highlight_roads(base_map_path, out_path):
    print("Loading road geometries...")
    roads_file = "data/source/santacruz_roads.geojson"
    roads = gpd.read_file(roads_file)
    roads_proj = roads.to_crs(epsg=3857)
    
    print("Loading map bounds...")
    with open("assets/maps/map.bounds.json", "r") as f:
        bounds = json.load(f)
        
    minx, miny = bounds["minx"], bounds["miny"]
    maxx, maxy = bounds["maxx"], bounds["maxy"]
    
    # Get image dimensions to match perfectly
    base_img = Image.open(base_map_path).convert('RGBA')
    img_width, img_height = base_img.size
    
    dpi = 100
    fig_width = img_width / dpi
    fig_height = img_height / dpi
    
    fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=dpi)
    
    # CRITICAL: Prevent stretching
    ax.set_aspect('equal')
    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)
    
    # Sleek glowing cyan/blue palette for Dark Mode highlighting
    ROAD_GLOW = "#00d2ff"
    ROAD_OUTER = "#1b2a47" 
    ROAD_INNER = "#3ca2ff"
    ROAD_ACCENT = "#ffffff"
    
    # Plot multi-layered roads
    print("Plotting road highlights...")
    outer_width = 6.0
    inner_width = 3.0
    
    # Outer glow
    roads_proj.plot(ax=ax, linewidth=outer_width + 4.0, color=ROAD_GLOW, alpha=0.15)
    # Border
    roads_proj.plot(ax=ax, linewidth=outer_width, color=ROAD_OUTER, alpha=0.8)
    # Inner path
    roads_proj.plot(ax=ax, linewidth=inner_width, color=ROAD_INNER, alpha=0.9)
    # Bright accent line
    roads_proj.plot(ax=ax, linewidth=max(1.0, inner_width * 0.3), color=ROAD_ACCENT, alpha=0.8)
    
    # Remove background entirely
    ax.axis("off")
    fig.patch.set_alpha(0)
    ax.patch.set_alpha(0)
    plt.subplots_adjust(left=0, bottom=0, right=1, top=1, wspace=0, hspace=0)
    
    temp_roads_path = "assets/maps/temp_roads.png"
    plt.savefig(temp_roads_path, dpi=dpi, bbox_inches='tight', pad_inches=0, transparent=True)
    plt.close(fig)
    
    print("Compositing roads over base map...")
    # Composite over base map
    roads_img = Image.open(temp_roads_path).convert('RGBA')
    
    # Ensure sizes match exactly before compositing
    if roads_img.size != base_img.size:
        print(f"Resizing roads overlay from {roads_img.size} to {base_img.size} to match perfectly...")
        roads_img = roads_img.resize(base_img.size, Image.Resampling.LANCZOS)
        
    combined = Image.alpha_composite(base_img, roads_img)
    combined.convert('RGB').save(out_path)
    print(f"Saved highlighted map to {out_path}")
    
    if os.path.exists(temp_roads_path):
        os.remove(temp_roads_path)

if __name__ == "__main__":
    base = "assets/maps/map.png"
    out = "assets/maps/map.png"
    highlight_roads(base, out)
