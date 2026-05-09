#!/usr/bin/env python3
"""Simple patrol route creator for Santa Cruz city center."""
import json
from pathlib import Path

def main():
    # Define patrol points in Santa Cruz city center (lat, lon)
    # These are major intersections and roads within the city
    patrol_points = [
        [14.2974, 121.3577],  # Starting point (city center)
        [14.3010, 121.3590],  # North along main road
        [14.3025, 121.3620],  # East turn
        [14.3045, 121.3650],  # Continue east
        [14.3060, 121.3680],  # Further east
        [14.3040, 121.3720],  # Southeast
        [14.3000, 121.3740],  # South
        [14.2980, 121.3710],  # Southwest
        [14.2960, 121.3680],  # West
        [14.2950, 121.3650],  # Continue west
        [14.2945, 121.3620],  # Northwest
        [14.2960, 121.3590],  # Back north
        [14.2974, 121.3577]   # Return to start
    ]
    
    # Load bounds for normalization
    try:
        bounds_file = Path("map.png.bounds.json")
        if bounds_file.exists():
            with open(bounds_file, "r") as f:
                bounds = json.load(f)
                minx, miny = bounds["minx"], bounds["miny"]
                maxx, maxy = bounds["maxx"], bounds["maxy"]
        else:
            # Use rough bounds for Santa Cruz area
            from pyproj import Transformer
            transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
            
            # Rough Santa Cruz bounds
            minlon, minlat = 121.35, 14.29
            maxlon, maxlat = 121.39, 14.31
            
            c1 = transformer.transform(minlon, minlat)
            c2 = transformer.transform(minlon, maxlat)
            c3 = transformer.transform(maxlon, minlat)
            c4 = transformer.transform(maxlon, maxlat)
            
            xs = [c1[0], c2[0], c3[0], c4[0]]
            ys = [c1[1], c2[1], c3[1], c4[1]]
            
            minx_base, maxx_base = min(xs), max(xs)
            miny_base, maxy_base = min(ys), max(ys)
            
            # Add padding
            padding = max(maxx_base - minx_base, maxy_base - miny_base) * 0.1
            minx = minx_base - padding
            maxx = maxx_base + padding
            miny = miny_base - padding
            maxy = maxy_base + padding
        
        # Convert patrol points to normalized coordinates
        from pyproj import Transformer
        transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
        
        points_norm = []
        for lat, lon in patrol_points:
            x, y = transformer.transform(lon, lat)
            nx = (x - minx) / (maxx - minx)
            ny = (y - miny) / (maxy - miny)
            points_norm.append([nx, ny])
        
        # Create patrol route data
        payload = {
            "type": "patrol_circuit",
            "waypoints": len(patrol_points),
            "total_points": len(points_norm),
            "points": points_norm,
            "is_loop": True
        }
        
        out_path = Path("data/patrol_route.json")
        out_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(out_path, "w") as f:
            json.dump(payload, f, indent=2)
        
        print(f"Created patrol route with {len(points_norm)} points")
        
    except Exception as e:
        print(f"Error creating patrol route: {e}")

if __name__ == "__main__":
    main()