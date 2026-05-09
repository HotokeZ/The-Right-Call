#!/usr/bin/env python3
"""Create patrol route using existing road points data."""
import json
from pathlib import Path

def main():
    # Load the existing road points that follow actual roads
    roads_points_file = Path("data/santacruz_roads_points.json")
    
    if not roads_points_file.exists():
        print("Road points file not found. Run export_normalized_points.py first.")
        return
    
    print("Loading existing road points...")
    with open(roads_points_file, "r") as f:
        road_data = json.load(f)
    
    all_points = road_data["points"]
    print(f"Loaded {len(all_points)} road points")
    
    # Create a patrol route by sampling points along the road network
    # Take every Nth point to create a manageable patrol circuit
    step_size = max(1, len(all_points) // 300)  # Target ~300 points for smooth but efficient patrol
    patrol_points = []
    
    for i in range(0, len(all_points), step_size):
        patrol_points.append(all_points[i])
    
    # Ensure the route loops back to start
    if len(patrol_points) > 1 and patrol_points[-1] != patrol_points[0]:
        patrol_points.append(patrol_points[0])
    
    print(f"Created patrol circuit with {len(patrol_points)} points")
    
    # Create patrol route data
    payload = {
        "type": "road_patrol",
        "description": "Route following actual road network points",
        "total_points": len(patrol_points),
        "points": patrol_points,
        "is_loop": True,
        "follows_roads": True,
        "source": "santacruz_roads_points.json"
    }
    
    out_path = Path("data/patrol_route.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2)
    
    print(f"Wrote road-following patrol route to {out_path}")
    print("This route follows the actual road geometries from the map")

if __name__ == "__main__":
    main()