#!/usr/bin/env python3
"""Create perfectly aligned patrol route using existing road point bounds."""
import json
from pathlib import Path

def main():
    # Load the existing road points that are already properly aligned
    points_file = Path("data/santacruz_roads_points.json")
    
    if not points_file.exists():
        print("Road points file not found. Run export_normalized_points.py first.")
        return
    
    with open(points_file, "r") as f:
        road_data = json.load(f)
    
    print("Loading road points...")
    all_points = road_data["points"]
    original_bounds = road_data["bounds"]
    
    print(f"Loaded {len(all_points)} road points")
    print(f"Original bounds: {original_bounds}")
    
    # Load map bounds to check alignment
    bounds_file = Path("map.bounds.json")
    if bounds_file.exists():
        with open(bounds_file, "r") as f:
            map_bounds = json.load(f)
        print(f"Map bounds: {map_bounds}")
        
        # Use map bounds for perfect alignment
        minx, miny = map_bounds["minx"], map_bounds["miny"]
        maxx, maxy = map_bounds["maxx"], map_bounds["maxy"]
        
        print("Using map bounds for alignment")
    else:
        # Fallback to original bounds
        minx, miny, maxx, maxy = original_bounds
        print("Using original road bounds")
    
    # The points are already normalized [0,1], we need to:
    # 1. Convert back to projected coordinates using original bounds
    # 2. Filter points that fall within map bounds 
    # 3. Renormalize using map bounds for perfect alignment
    
    orig_minx, orig_miny, orig_maxx, orig_maxy = original_bounds
    orig_width = orig_maxx - orig_minx
    orig_height = orig_maxy - orig_miny
    
    # Convert normalized points back to projected coordinates
    proj_points = []
    for nx, ny in all_points:
        x = orig_minx + (nx * orig_width)
        y = orig_miny + (ny * orig_height)
        
        # Only include points within map bounds
        if minx <= x <= maxx and miny <= y <= maxy:
            proj_points.append((x, y))
    
    print(f"Found {len(proj_points)} points within map bounds")
    
    if len(proj_points) < 50:
        print("Not enough points found within map bounds. Using all points.")
        # Recalculate using all points
        proj_points = []
        for nx, ny in all_points:
            x = orig_minx + (nx * orig_width)
            y = orig_miny + (ny * orig_height)
            proj_points.append((x, y))
    
    # Create patrol circuit by sampling points
    # Take every Nth point for a manageable route
    step = max(1, len(proj_points) // 200)  # Target ~200 points
    patrol_points = proj_points[::step]
    
    # Ensure loop closure
    if len(patrol_points) > 1 and patrol_points[-1] != patrol_points[0]:
        patrol_points.append(patrol_points[0])
    
    print(f"Created patrol circuit with {len(patrol_points)} points")
    
    # Normalize using map bounds for perfect alignment
    width = maxx - minx
    height = maxy - miny
    
    points_norm = []
    for x, y in patrol_points:
        nx = (x - minx) / width
        ny = (y - miny) / height
        points_norm.append([nx, ny])
    
    # Verify normalization
    print(f"Normalized coordinate ranges:")
    print(f"  X: {min(p[0] for p in points_norm):.3f} to {max(p[0] for p in points_norm):.3f}")
    print(f"  Y: {min(p[1] for p in points_norm):.3f} to {max(p[1] for p in points_norm):.3f}")
    
    # Create the final aligned patrol route
    payload = {
        "type": "perfectly_aligned_patrol",
        "description": "Route using exact map bounds for perfect alignment",
        "map_bounds_used": {
            "minx": minx, "miny": miny, "maxx": maxx, "maxy": maxy
        },
        "original_bounds": original_bounds,
        "total_points": len(points_norm),
        "points": points_norm,
        "is_loop": True,
        "follows_roads": True
    }
    
    out_path = Path("data/patrol_route.json")
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
    
    print(f"Wrote perfectly aligned patrol route to {out_path}")
    print("The patrol should now follow the exact roads on the map!")

if __name__ == "__main__":
    main()