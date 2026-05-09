import json
import geopandas as gpd
import contextily as ctx
import matplotlib.pyplot as plt
from PIL import Image
import numpy as np
import os

def generate_interactive_maps():
    bounds_file = "assets/maps/map.bounds.json"
    with open(bounds_file, "r") as f:
        bounds = json.load(f)
    minx, miny, maxx, maxy = bounds["minx"], bounds["miny"], bounds["maxx"], bounds["maxy"]
    
    # Base dimensions for zoom 15 (our standard 1468x2048)
    base_height = 2048
    ratio = (maxx - minx) / (maxy - miny)
    base_width = int(base_height * ratio)
    print(f"Base aspect ratio: {ratio:.4f}")
    
    # We will use geopandas to create an inverted mask (World minus Santa Cruz)
    from shapely.geometry import box
    print("Preparing geographic mask...")
    world = gpd.GeoDataFrame(geometry=[box(-180, -90, 180, 90)], crs="EPSG:4326").to_crs(epsg=3857)
    
    place = gpd.read_file("data/source/santacruz_place.geojson").to_crs(epsg=3857)
    inverted_mask = gpd.overlay(world, place, how='difference')
    
    def process_map_layer(zoom_level, output_filename, dpi_scale):
        print(f"Generating {output_filename} (zoom {zoom_level}, scale {dpi_scale}x)...")
        dpi = 100 * dpi_scale
        fig_width = base_width / 100
        fig_height = base_height / 100
        
        fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=dpi)
        fig.patch.set_facecolor('#000000')
        ax.set_facecolor('#000000')
        
        # Enforce exact bounds
        ax.set_xlim(minx, maxx)
        ax.set_ylim(miny, maxy)
        ax.set_aspect('equal')
        ax.axis("off")
        plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
        
        print(f"Fetching tiles for {output_filename}...")
        import time
        max_retries = 3
        for attempt in range(max_retries):
            try:
                # Use OpenStreetMap.Mapnik for more resilient tile fetching and detailed structures
                ctx.add_basemap(ax, source=ctx.providers.OpenStreetMap.Mapnik, zoom=zoom_level)
                break
            except Exception as e:
                print(f"Failed to fetch tiles (attempt {attempt+1}): {e}")
                if attempt == max_retries - 1:
                    plt.close(fig)
                    return False
                time.sleep(5)
            
        temp_base = f"assets/maps/temp_{zoom_level}.png"
        fig.savefig(temp_base, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#000000')
        plt.close(fig)
        
        print(f"Colorizing and masking {output_filename}...")
        img = Image.open(temp_base).convert('L')
        
        # OSM Mapnik is a light map. We must invert it so it behaves like DarkMatter
        # before applying our Google Night Mode color mapping.
        from PIL import ImageOps
        img = ImageOps.invert(img)
        
        arr = np.array(img).astype(float)
        
        # Color mapping to Google Night Mode style
        x = [0, 25, 55, 100, 255]
        y_r = [22, 34, 59, 83, 200]
        y_g = [29, 43, 70, 99, 208]
        y_b = [41, 60, 92, 128, 223]
        
        r = np.interp(arr, x, y_r)
        g = np.interp(arr, x, y_g)
        b = np.interp(arr, x, y_b)
        colored_arr = np.dstack((r, g, b)).astype(np.uint8)
        
        # Re-plot the colorized image with the inverted mask on top
        fig, ax = plt.subplots(figsize=(fig_width, fig_height), dpi=dpi)
        fig.patch.set_facecolor('#111620')
        ax.set_facecolor('#111620')
        ax.set_xlim(minx, maxx)
        ax.set_ylim(miny, maxy)
        ax.set_aspect('equal')
        ax.axis("off")
        plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
        
        ax.imshow(colored_arr, extent=(minx, maxx, miny, maxy))
        
        # Draw the inverted mask to cut off non-Santa Cruz areas
        # Dark void color matching Google Maps off-bounds regions
        inverted_mask.plot(ax=ax, color='#111620', alpha=1.0)
        
        fig.savefig(output_filename, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#111620')
        plt.close(fig)
        
        if os.path.exists(temp_base): os.remove(temp_base)
        print(f"Finished {output_filename}")
        return True

    # Generate Map Low (Zoom 15, native size ~1468x2048)
    process_map_layer(15, "assets/maps/map_low.png", dpi_scale=1)
    
    # Generate Map High (Zoom 16, native size ~2936x4096)
    # This guarantees the exact same bounding box mathematically, just twice the pixel density.
    process_map_layer(16, "assets/maps/map_high.png", dpi_scale=2)
    
    print("All interactive map layers generated successfully!")

if __name__ == "__main__":
    generate_interactive_maps()
