import json
import geopandas as gpd
import contextily as ctx
import matplotlib.pyplot as plt
from PIL import Image
import numpy as np
import os

def rebuild_map():
    bounds_file = "assets/maps/map.bounds.json"
    with open(bounds_file, "r") as f:
        bounds = json.load(f)
    minx, miny, maxx, maxy = bounds["minx"], bounds["miny"], bounds["maxx"], bounds["maxy"]
    
    # 1. Calculate exact width to match the aspect ratio of the bounds
    # The backup map had a height of 2048 and width 1468.
    target_height = 2048
    ratio = (maxx - minx) / (maxy - miny)
    target_width = int(target_height * ratio)
    print(f"Calculated dimensions: {target_width}x{target_height} (Ratio: {ratio:.4f})")
    
    dpi = 100
    fig_width = target_width / dpi
    fig_height = target_height / dpi
    
    # 2. GENERATE BASE MAP
    print("Fetching CartoDB DarkMatter tiles...")
    fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=dpi)
    fig.patch.set_facecolor('#000000')
    ax.set_facecolor('#000000')
    
    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)
    ax.set_aspect('equal')
    ax.axis("off")
    plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
    
    try:
        ctx.add_basemap(ax, source=ctx.providers.CartoDB.DarkMatter, zoom=15)
    except Exception as e:
        print(f"Basemap failed: {e}")
        return
        
    temp_base = "assets/maps/temp_base.png"
    fig.savefig(temp_base, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#000000')
    plt.close(fig)
    
    # 3. COLORIZE BASE MAP TO MATCH REFERENCE
    print("Colorizing base map...")
    img = Image.open(temp_base).convert('L')
    if img.size != (target_width, target_height):
        img = img.resize((target_width, target_height), Image.Resampling.LANCZOS)
        
    arr = np.array(img).astype(float)
    x = [0, 25, 55, 100, 255]
    y_r = [22, 34, 59, 83, 200]
    y_g = [29, 43, 70, 99, 208]
    y_b = [41, 60, 92, 128, 223]
    r = np.interp(arr, x, y_r)
    g = np.interp(arr, x, y_g)
    b = np.interp(arr, x, y_b)
    out_arr = np.dstack((r, g, b)).astype(np.uint8)
    base_img = Image.fromarray(out_arr).convert('RGBA')
    
    # 4. GENERATE ROAD OVERLAY (Muted soft colors matching reference)
    print("Generating road overlay...")
    fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=dpi)
    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)
    ax.set_aspect('equal')
    ax.axis("off")
    fig.patch.set_alpha(0)
    ax.patch.set_alpha(0)
    plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
    
    roads = gpd.read_file("data/source/santacruz_roads.geojson").to_crs(epsg=3857)
    
    # Use soft blue/grey colors from the reference image, no glowing neon
    ROAD_BASE = "#3b465c"
    ROAD_CENTER = "#536380"
    
    roads.plot(ax=ax, linewidth=2.5, color=ROAD_BASE, alpha=1.0)
    roads.plot(ax=ax, linewidth=0.8, color=ROAD_CENTER, alpha=0.8)
    
    temp_roads = "assets/maps/temp_roads.png"
    plt.savefig(temp_roads, dpi=dpi, bbox_inches="tight", pad_inches=0, transparent=True)
    plt.close(fig)
    
    roads_img = Image.open(temp_roads).convert('RGBA')
    if roads_img.size != (target_width, target_height):
        roads_img = roads_img.resize((target_width, target_height), Image.Resampling.LANCZOS)
        
    print("Compositing...")
    combined = Image.alpha_composite(base_img, roads_img)
    combined.convert('RGB').save("assets/maps/map.png")
    
    if os.path.exists(temp_base): os.remove(temp_base)
    if os.path.exists(temp_roads): os.remove(temp_roads)
    print(f"Successfully rebuilt map.png at {target_width}x{target_height}")

if __name__ == "__main__":
    rebuild_map()
