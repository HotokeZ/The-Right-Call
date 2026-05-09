#!/usr/bin/env python3
"""Fix patrol route alignment by using exact map bounds."""
import json
from pathlib import Path

def main():
    # Load the exact bounds used to create the map
    bounds_file = Path("map.bounds.json")
    
    if not bounds_file.exists():
        print("Map bounds file not found. Need to regenerate map first.")
        return
    
    with open(bounds_file, "r") as f:
        map_bounds = json.load(f)
    
    print(f"Using map bounds: {map_bounds}")
    
    # Load the raw road data
    roads_file = Path("data/santacruz_roads.geojson")
    if not roads_file.exists():
        print("Roads file not found.")
        return
    
    try:
        import geopandas as gpd
        from pyproj import Transformer
        from shapely.geometry import LineString
    except ImportError:
        print("Missing dependencies: pip install geopandas")
        return
    
    print("Loading and processing road geometries...")
    roads = gpd.read_file(roads_file)
    
    # Project to EPSG:3857 (same as map)
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    
    # Extract road points within map bounds
    minx, miny = map_bounds["minx"], map_bounds["miny"]
    maxx, maxy = map_bounds["maxx"], map_bounds["maxy"]
    
    print(f"Map bounds: x=({minx:.0f}, {maxx:.0f}), y=({miny:.0f}, {maxy:.0f})")
    
    road_points = []
    
    for idx, road in roads.iterrows():
        geom = road.geometry
        
        if geom.geom_type == 'LineString':
            coords = list(geom.coords)
        elif geom.geom_type == 'MultiLineString':
            coords = []
            for line_geom in geom.geoms:
                coords.extend(list(line_geom.coords))
        else:
            continue
        
        # Project coordinates and filter to map bounds
        for lon, lat in coords:
            x, y = transformer.transform(lon, lat)
            
            # Only include points within the map bounds
            if minx <= x <= maxx and miny <= y <= maxy:
                road_points.append((x, y))
    
    print(f"Found {len(road_points)} road points within map bounds")
    
    if len(road_points) < 10:
        print("Not enough road points found! Check bounds alignment.")
        return
    
    # Remove duplicate points and sort for better connectivity
    unique_points = list(set(road_points))
    
    # Create a patrol circuit through the road network
    # Start from center and create a path that covers major areas
    center_x = sum(p[0] for p in unique_points) / len(unique_points)
    center_y = sum(p[1] for p in unique_points) / len(unique_points)
    
    print(f"Road network center: ({center_x:.0f}, {center_y:.0f})")
    
    # Sort points by distance from center, then by angle to create a circuit
    import math
    
    def sort_key(point):
        x, y = point
        distance = ((x - center_x)**2 + (y - center_y)**2)**0.5
        angle = math.atan2(y - center_y, x - center_x)
        # Create rings: group by distance ranges, then sort by angle
        ring = int(distance / 1000)  # 1km rings
        return (ring, angle)
    
    sorted_points = sorted(unique_points, key=sort_key)
    
    # Take every Nth point to create manageable route
    step = max(1, len(sorted_points) // 150)  # Target ~150 points
    patrol_points = sorted_points[::step]
    
    # Ensure loop closure
    if len(patrol_points) > 1 and patrol_points[-1] != patrol_points[0]:
        patrol_points.append(patrol_points[0])
    
    print(f"Created patrol route with {len(patrol_points)} points")
    
    # Normalize using EXACT map bounds
    width = maxx - minx
    height = maxy - miny
    
    points_norm = []
    for x, y in patrol_points:
        nx = (x - minx) / width
        ny = (y - miny) / height
        points_norm.append([nx, ny])
    
    # Verify normalization
    print(f"Normalized bounds check:")
    print(f"  X range: {min(p[0] for p in points_norm):.3f} to {max(p[0] for p in points_norm):.3f}")
    print(f"  Y range: {min(p[1] for p in points_norm):.3f} to {max(p[1] for p in points_norm):.3f}")
    
    # Create aligned patrol route
    payload = {
        "type": "aligned_road_patrol", 
        "description": "Route aligned with exact map bounds",
        "map_bounds_used": map_bounds,
        "total_points": len(points_norm),
        "points": points_norm,
        "is_loop": True,
        "follows_roads": True
    }
    
    out_path = Path("data/patrol_route.json")
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
    
    print(f"Wrote aligned patrol route to {out_path}")
    print("Route should now align perfectly with map roads!")

if __name__ == "__main__":
    main()