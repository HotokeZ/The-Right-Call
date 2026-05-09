#!/usr/bin/env python3
"""Extract actual road segments for patrol route following real map roads."""
import json
from pathlib import Path
import geopandas as gpd
from shapely.geometry import Point, LineString
from pyproj import Transformer
import networkx as nx

def main():
    try:
        import osmnx as ox
    except ImportError:
        print("Missing dependency: pip install osmnx")
        return

    # Load the roads that were used to create the map
    roads_file = Path("data/santacruz_roads.geojson")
    if not roads_file.exists():
        print("Roads file not found. Run OSM extraction first.")
        return

    print("Loading road network...")
    roads = gpd.read_file(roads_file)
    
    # Filter for main roads only
    main_roads = roads[roads['highway'].isin([
        'primary', 'secondary', 'trunk', 'primary_link', 'secondary_link',
        'tertiary', 'residential'  # Include more road types
    ])]
    
    if len(main_roads) == 0:
        # Fallback: use all roads
        main_roads = roads
    
    print(f"Using {len(main_roads)} road segments")
    
    # Project to EPSG:3857 for distance calculations
    transformer = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    
    # Get all road geometries and sample points along them
    all_points = []
    
    for idx, road in main_roads.iterrows():
        geom = road.geometry
        if geom.geom_type == 'LineString':
            coords = list(geom.coords)
            # Project coordinates
            proj_coords = [transformer.transform(lon, lat) for lon, lat in coords]
            
            # Sample points along this road segment (every 50 meters)
            line = LineString(proj_coords)
            length = line.length
            if length > 0:
                num_points = max(2, int(length / 50))  # Point every 50m
                for i in range(num_points):
                    fraction = i / (num_points - 1) if num_points > 1 else 0
                    point = line.interpolate(fraction * length)
                    all_points.append((point.x, point.y))
        elif geom.geom_type == 'MultiLineString':
            for line_geom in geom.geoms:
                coords = list(line_geom.coords)
                proj_coords = [transformer.transform(lon, lat) for lon, lat in coords]
                line = LineString(proj_coords)
                length = line.length
                if length > 0:
                    num_points = max(2, int(length / 50))
                    for i in range(num_points):
                        fraction = i / (num_points - 1) if num_points > 1 else 0
                        point = line.interpolate(fraction * length)
                        all_points.append((point.x, point.y))
    
    if not all_points:
        print("No road points found!")
        return
    
    print(f"Extracted {len(all_points)} road points")
    
    # Create a continuous path through the road network
    # Start from center and create a circuit
    center_x = sum(p[0] for p in all_points) / len(all_points)
    center_y = sum(p[1] for p in all_points) / len(all_points)
    
    # Sort points by distance from center to create a roughly circular path
    def distance_from_center(point):
        return ((point[0] - center_x) ** 2 + (point[1] - center_y) ** 2) ** 0.5
    
    # Group points by distance ranges to create a spiral/circuit pattern
    sorted_points = sorted(all_points, key=lambda p: (
        distance_from_center(p),
        # Add angle component to create circuit
        __import__('math').atan2(p[1] - center_y, p[0] - center_x)
    ))
    
    # Take a subset for the patrol route (every 10th point to avoid too dense)
    patrol_points = []
    step = max(1, len(sorted_points) // 200)  # Target ~200 points max
    for i in range(0, len(sorted_points), step):
        patrol_points.append(sorted_points[i])
    
    # Ensure the route loops back to start
    if len(patrol_points) > 1 and patrol_points[-1] != patrol_points[0]:
        patrol_points.append(patrol_points[0])
    
    print(f"Created patrol circuit with {len(patrol_points)} points")
    
    # Load bounds for normalization
    bounds_file = Path("map.png.bounds.json")
    bbox_path = Path("data/santacruz_bbox.json")
    
    if bounds_file.exists():
        with open(bounds_file, "r") as f:
            bounds = json.load(f)
            minx, miny = bounds["minx"], bounds["miny"]
            maxx, maxy = bounds["maxx"], bounds["maxy"]
    elif bbox_path.exists():
        with open(bbox_path, "r") as f:
            meta = json.load(f)
            bounds_data = meta.get("bounds")
            if isinstance(bounds_data[0], (list, tuple)):
                minlon, minlat, maxlon, maxlat = bounds_data[0]
            else:
                minlon, minlat, maxlon, maxlat = bounds_data

        c1 = transformer.transform(minlon, minlat)
        c2 = transformer.transform(minlon, maxlat)
        c3 = transformer.transform(maxlon, minlat)
        c4 = transformer.transform(maxlon, maxlat)
        xs = [c1[0], c2[0], c3[0], c4[0]]
        ys = [c1[1], c2[1], c3[1], c4[1]]
        minx_base, maxx_base = min(xs), max(xs)
        miny_base, maxy_base = min(ys), max(ys)
        
        padding = max(maxx_base - minx_base, maxy_base - miny_base) * 0.1
        minx = minx_base - padding
        maxx = maxx_base + padding
        miny = miny_base - padding
        maxy = maxy_base + padding
    else:
        xs = [x for x, y in patrol_points]
        ys = [y for x, y in patrol_points]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)
    
    width = maxx - minx if maxx - minx != 0 else 1.0
    height = maxy - miny if maxy - miny != 0 else 1.0
    
    # Normalize coordinates
    points_norm = []
    for x, y in patrol_points:
        nx = (x - minx) / width
        ny = (y - miny) / height
        points_norm.append([nx, ny])
    
    # Create road-following patrol route
    payload = {
        "type": "road_patrol",
        "description": "Route following actual road geometries",
        "total_points": len(points_norm),
        "points": points_norm,
        "is_loop": True,
        "follows_roads": True
    }
    
    out_path = Path("data/patrol_route.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
    
    print(f"Wrote road-following patrol route to {out_path}")
    print(f"Route has {len(points_norm)} points following actual roads")

if __name__ == "__main__":
    main()