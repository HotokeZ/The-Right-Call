import json
import contextily as ctx
import matplotlib.pyplot as plt
from pyproj import Transformer
from PIL import Image, ImageOps, ImageEnhance
import os

def create_map(provider, out_path, as_slate=False):
    bbox_path = "data/source/santacruz_bbox.json"
    
    meta = json.load(open(bbox_path, "r", encoding="utf-8"))
    bounds = meta["bounds"]
    if isinstance(bounds[0], (list, tuple)):
        minlon, minlat, maxlon, maxlat = bounds[0]
    else:
        minlon, minlat, maxlon, maxlat = bounds

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    minx, miny = transformer.transform(minlon, minlat)
    maxx, maxy = transformer.transform(maxlon, maxlat)

    padding = max(maxx - minx, maxy - miny) * 0.1
    minx -= padding
    maxx += padding
    miny -= padding
    maxy += padding

    dpi = 100
    width = 2048
    height = 2048
    fig, ax = plt.subplots(figsize=(width/dpi, height/dpi), dpi=dpi)
    fig.patch.set_facecolor('#000000')
    ax.set_facecolor('#000000')

    # THIS IS CRITICAL: prevents stretching and preserves exact real-world proportions
    ax.set_aspect('equal')
    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)

    print(f"Fetching tiles for {out_path}...")
    try:
        ctx.add_basemap(
            ax,
            source=provider,
            zoom=15, 
        )
    except Exception as exc:
        print(f"Basemap failed: {exc}")
        return False

    ax.axis("off")
    plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
    
    if as_slate:
        temp_path = "assets/maps/temp_light.png"
        fig.savefig(temp_path, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#000000')
        plt.close(fig)
        
        # Make a sleek slate/dark map from the detailed light map
        img = Image.open(temp_path).convert('L') # Grayscale removes harsh clashing colors
        inv = ImageOps.invert(img) # Invert lightness
        
        # Colorize to make it look like a sleek UI map
        slate_map = ImageOps.colorize(inv, black="#0f141e", white="#8b9bb4", mid="#2a364f")
        
        slate_map.save(out_path)
        if os.path.exists(temp_path):
            os.remove(temp_path)
    else:
        fig.savefig(out_path, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#000000')
        plt.close(fig)
        
    print(f"Saved {out_path}")
    return True

if __name__ == "__main__":
    # Option 1: True Dark Mode (CartoDB DarkMatter)
    create_map(ctx.providers.CartoDB.DarkMatter, "assets/maps/map.png", as_slate=False)
    
    # Option 2: Highly Detailed Slate (OSM Mapnik -> Grayscale Invert Tint)
    create_map(ctx.providers.OpenStreetMap.Mapnik, "assets/maps/map_detailed_slate.png", as_slate=True)
