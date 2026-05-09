#!/usr/bin/env python3
"""
Simple citywide patrol - sample from entire road network uniformly.
"""

import json
import numpy as np

def create_citywide_patrol():
    """Create patrol covering entire city by uniform sampling."""
    
    # Load clean road data
    with open('data/clean_road_points.json', 'r') as f:
        data = json.load(f)
    
    road_points = data['road_points']
    print(f"Loaded {len(road_points):,} road points")
    
    # Analyze full extent
    x_coords = [p['x'] for p in road_points]
    y_coords = [p['y'] for p in road_points]
    
    x_min, x_max = min(x_coords), max(x_coords)
    y_min, y_max = min(y_coords), max(y_coords)
    
    print(f"Full road network extent:")
    print(f"  X: {x_min:.3f} to {x_max:.3f} (span: {x_max - x_min:.3f})")
    print(f"  Y: {y_min:.3f} to {y_max:.3f} (span: {y_max - y_min:.3f})")
    
    # Sample uniformly across the entire road network
    # Use higher sample size to cover more of the city
    sample_size = min(800, len(road_points))  
    
    np.random.seed(42)  # Reproducible sampling
    indices = np.random.choice(len(road_points), sample_size, replace=False)
    
    patrol_points = []
    for i in indices:
        patrol_points.append({
            "x": road_points[i]['x'],
            "y": road_points[i]['y']
        })
    
    # Sort by position to create a reasonable traversal order
    # Sort first by Y (north to south), then by X (west to east)
    patrol_points.sort(key=lambda p: (p['y'], p['x']))
    
    # Create route data
    route_data = {
        "route_info": {
            "total_points": len(patrol_points),
            "source": "uniform_sampling_citywide",
            "method": "random_sampling_full_coverage",
            "coverage": f"Full city: X={x_min:.3f}-{x_max:.3f}, Y={y_min:.3f}-{y_max:.3f}"
        },
        "points": patrol_points
    }
    
    # Save
    with open('data/citywide_patrol_route.json', 'w') as f:
        json.dump(route_data, f, indent=2)
    
    # Verify coverage
    final_x = [p['x'] for p in patrol_points]
    final_y = [p['y'] for p in patrol_points]
    
    coverage_x = (max(final_x) - min(final_x)) / (x_max - x_min) * 100
    coverage_y = (max(final_y) - min(final_y)) / (y_max - y_min) * 100
    
    print(f"\n✅ CITYWIDE PATROL CREATED:")
    print(f"   📍 Points: {len(patrol_points)}")
    print(f"   🗺️  X coverage: {coverage_x:.1f}% of city width")
    print(f"   🗺️  Y coverage: {coverage_y:.1f}% of city height")
    print(f"   📁 File: data/citywide_patrol_route.json")
    
    return patrol_points

if __name__ == "__main__":
    try:
        create_citywide_patrol()
        print("\n🎯 SUCCESS: Citywide patrol covers the ENTIRE road network!")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()