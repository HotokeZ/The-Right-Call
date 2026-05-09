import json
import contextily as ctx
import matplotlib.pyplot as plt
from pyproj import Transformer
from PIL import Image, ImageOps, ImageEnhance
import os

def create_map(provider, out_path):
    bbox_path = "data/source/santacruz_bbox.json"
    
    meta = json.load(open(bbox_path, "r", encoding="utf-8"))
    if isinstance(meta["bounds"][0], (list, tuple)):
        minlon, minlat, maxlon, maxlat = meta["bounds"][0]
    else:
        minlon, minlat, maxlon, maxlat = meta["bounds"]

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

    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)

    print(f"Fetching tiles using {provider}...")
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
    
    fig.savefig(out_path, dpi=dpi, bbox_inches="tight", pad_inches=0, facecolor='#000000')
    plt.close(fig)
    print(f"Saved {out_path}")
    return True

def smart_dark_mode(input_path, output_path):
    img = Image.open(input_path).convert('RGB')
    
    # Invert the image
    inv = ImageOps.invert(img)
    
    # The inverted image will have orange water (inverted blue).
    # We can shift hue or just desaturate the inverted map to make it a sleek dark gray map.
    converter = ImageEnhance.Color(inv)
    desat = converter.enhance(0.2) # almost grayscale
    
    # Darken it a bit more
    darkener = ImageEnhance.Brightness(desat)
    final = darkener.enhance(0.8)
    
    final.save(output_path)
    print(f"Saved dark mode version to {output_path}")

def main():
    # 1. Try CartoDB DarkMatter (native dark map)
    create_map(ctx.providers.CartoDB.DarkMatter, "assets/maps/map_darkmatter.png")
    
    # 2. Try OSM Humanitarian (detailed) and convert to dark mode
    if create_map(ctx.providers.OpenStreetMap.HOT, "assets/maps/map_hot_light.png"):
        smart_dark_mode("assets/maps/map_hot_light.png", "assets/maps/map.png")
        # Clean up temp
        if os.path.exists("assets/maps/map_hot_light.png"):
            os.remove("assets/maps/map_hot_light.png")

if __name__ == "__main__":
    main()
