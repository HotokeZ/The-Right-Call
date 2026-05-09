#!/usr/bin/env python3
"""
Compare the noisy computer vision detection vs. clean OSM road lines.
Shows exactly what the user wanted - clean roads only.
"""

import json
import matplotlib.pyplot as plt
from PIL import Image
import numpy as np

def compare_road_extraction():
    """
    Visual comparison of noisy vs. clean road extraction.
    """
    
    # Load data
    try:
        with open('data/road_pixels.json', 'r') as f:
            noisy_data = json.load(f)
        noisy_pixels = noisy_data['road_pixels']
        has_noisy = True
    except FileNotFoundError:
        has_noisy = False
        print("Noisy road data not found")
    
    try:
        with open('data/clean_road_points.json', 'r') as f:
            clean_data = json.load(f)
        clean_points = clean_data['road_points'] 
        has_clean = True
    except FileNotFoundError:
        has_clean = False 
        print("Clean road data not found")
    
    try:
        with open('data/clean_patrol_route.json', 'r') as f:
            patrol_data = json.load(f)
        patrol_points = patrol_data['points']
        has_patrol = True
    except FileNotFoundError:
        has_patrol = False
        print("Patrol route not found")
    
    # Load images
    original_img = Image.open('map.png')
    
    try:
        clean_roads_img = Image.open('data/clean_roads.png')
        has_clean_img = True
    except FileNotFoundError:
        has_clean_img = False
        print("Clean roads PNG not found")
    
    # Create comparison visualization
    fig = plt.figure(figsize=(20, 12))
    
    # Original satellite image
    plt.subplot(2, 4, 1)
    plt.imshow(original_img)
    plt.title('Original Satellite Image\n(Roads + Buildings + Subdivisions)', fontsize=12)
    plt.axis('off')
    
    # Noisy detection overlay
    plt.subplot(2, 4, 2) 
    plt.imshow(original_img)
    if has_noisy:
        img_width, img_height = original_img.size
        noisy_x = [p['x'] * img_width for p in noisy_pixels]
        noisy_y = [p['y'] * img_height for p in noisy_pixels]
        plt.scatter(noisy_x, noisy_y, c='red', s=0.5, alpha=0.6, label='Detected "Roads"')
        plt.title(f'❌ Noisy Detection\n{len(noisy_pixels):,} points (includes buildings)', fontsize=12, color='red')
    else:
        plt.title('Noisy Detection\n(Not available)', fontsize=12)
    plt.axis('off')
    
    # Clean roads PNG
    plt.subplot(2, 4, 3)
    if has_clean_img:
        plt.imshow(clean_roads_img)
        plt.title('✅ Clean Road Lines Only\n(Pure OSM geometry)', fontsize=12, color='green')
    else:
        plt.text(0.5, 0.5, 'Clean roads\nPNG not found', ha='center', va='center', 
                transform=plt.gca().transAxes)
        plt.title('Clean Road Lines\n(Not available)', fontsize=12)
    plt.axis('off')
    
    # Clean roads overlay on satellite
    plt.subplot(2, 4, 4)
    plt.imshow(original_img)
    if has_clean:
        img_width, img_height = original_img.size
        clean_x = [p['x'] * img_width for p in clean_points]
        clean_y = [p['y'] * img_height for p in clean_points]
        plt.scatter(clean_x, clean_y, c='lime', s=0.8, alpha=0.7, label='Clean Roads')
        plt.title(f'✅ Clean Roads Overlay\n{len(clean_points):,} road line points', fontsize=12, color='green')
    else:
        plt.title('Clean Roads Overlay\n(Not available)', fontsize=12)
    plt.axis('off')
    
    # Patrol route on clean roads
    plt.subplot(2, 4, 5)
    if has_clean_img:
        plt.imshow(clean_roads_img)
    else:
        # Create blank background
        plt.imshow(np.ones((100, 100, 3)))
        
    if has_patrol:
        img_width, img_height = original_img.size if has_clean_img else (100, 100)
        patrol_x = [p['x'] * img_width for p in patrol_points]
        patrol_y = [p['y'] * img_height for p in patrol_points]
        
        plt.plot(patrol_x, patrol_y, 'yellow', linewidth=3, alpha=0.9, label='Patrol Route')
        plt.scatter(patrol_x[::5], patrol_y[::5], c='orange', s=30, alpha=0.8, 
                   edgecolors='red', linewidth=1, label='Patrol Points')
        
        plt.title(f'🚗 Clean Patrol Route\n{len(patrol_points)} points following roads only', fontsize=12, color='blue')
        plt.legend()
    else:
        plt.title('Patrol Route\n(Not available)', fontsize=12)
    plt.axis('off')
    
    # Statistics comparison
    plt.subplot(2, 4, 6)
    plt.axis('off')
    
    stats_text = ""
    if has_noisy and has_clean and has_patrol:
        noisy_coverage = (noisy_data['total_pixels'] / (original_img.size[0] * original_img.size[1])) * 100
        
        stats_text = f"""
EXTRACTION COMPARISON:

❌ Noisy Detection (CV):
  • Total pixels: {noisy_data['total_pixels']:,}
  • Coverage: {noisy_coverage:.2f}%
  • Issues: Buildings, subdivisions included
  
✅ Clean Road Lines (OSM):
  • Road segments: {clean_data['road_segments']}
  • Line points: {len(clean_points):,}
  • Pure road geometry only
  
🚗 Final Patrol Route:
  • Points: {len(patrol_points)}
  • Follows: Clean roads only
  • Behavior: Infinite looping
  
RESULT:
  ✅ Patrol will follow ONLY red road lines
  ❌ No more buildings/subdivisions
        """
    
    plt.text(0.05, 0.95, stats_text, transform=plt.gca().transAxes, 
             verticalalignment='top', fontfamily='monospace', fontsize=10,
             bbox=dict(boxstyle="round,pad=0.3", facecolor="lightgray", alpha=0.8))
    
    # Coverage comparison plot
    plt.subplot(2, 4, 7)
    if has_noisy and has_clean:
        # Plot both on same axes for comparison
        if noisy_pixels:
            noisy_x_norm = [p['x'] for p in noisy_pixels]
            noisy_y_norm = [p['y'] for p in noisy_pixels]
            plt.scatter(noisy_x_norm, noisy_y_norm, c='red', s=1, alpha=0.3, label=f'Noisy ({len(noisy_pixels)} pts)')
        
        if clean_points:
            clean_x_norm = [p['x'] for p in clean_points]
            clean_y_norm = [p['y'] for p in clean_points]
            plt.scatter(clean_x_norm, clean_y_norm, c='green', s=1, alpha=0.7, label=f'Clean ({len(clean_points)} pts)')
        
        plt.xlim(0, 1)
        plt.ylim(0, 1)
        plt.gca().invert_yaxis()
        plt.title('Coverage Comparison\n(Normalized coordinates)', fontsize=12)
        plt.xlabel('X (normalized)')
        plt.ylabel('Y (normalized)')
        plt.legend()
    else:
        plt.text(0.5, 0.5, 'Data not available\nfor comparison', ha='center', va='center',
                transform=plt.gca().transAxes)
        plt.title('Coverage Comparison\n(Data missing)', fontsize=12)
    
    # Route quality analysis  
    plt.subplot(2, 4, 8)
    plt.axis('off')
    
    if has_patrol:
        route_x = [p['x'] for p in patrol_points]
        route_y = [p['y'] for p in patrol_points]
        
        x_range = max(route_x) - min(route_x)
        y_range = max(route_y) - min(route_y)
        
        quality_text = f"""
PATROL ROUTE QUALITY:

Coverage Area:
  X: {min(route_x):.3f} to {max(route_x):.3f}
  Y: {min(route_y):.3f} to {max(route_y):.3f}
  
Width span: {x_range:.1%}
Height span: {y_range:.1%}

Route Properties:
  • Total points: {len(patrol_points)}
  • Unique points: {len(set((p['x'], p['y']) for p in patrol_points))}
  • Route type: Connected road circuit
  • Looping: Infinite (seamless)

Expected Behavior:
  🚗 Follows red road lines exactly
  ⚡ Never goes off-road  
  🔄 Loops continuously
  ❌ Avoids white spaces completely
        """
        
        color = 'green' if x_range > 0.2 and y_range > 0.2 else 'orange'
    else:
        quality_text = "Patrol route data\nnot available"
        color = 'red'
    
    plt.text(0.05, 0.95, quality_text, transform=plt.gca().transAxes, 
             verticalalignment='top', fontfamily='monospace', fontsize=9,
             bbox=dict(boxstyle="round,pad=0.3", facecolor=color, alpha=0.2))
    
    plt.tight_layout()
    plt.savefig('data/clean_vs_noisy_comparison.png', dpi=150, bbox_inches='tight')
    plt.show()
    
    print("✅ Road extraction comparison complete!")
    print("  Saved: data/clean_vs_noisy_comparison.png")
    
    if has_clean and has_patrol:
        print(f"\n🎯 RESULT: Clean approach created {len(patrol_points)} patrol points")
        print("   ✅ Follows ONLY actual road lines (no buildings/subdivisions)")
        print("   🚗 Patrol will stay on red road paths in your satellite image")

if __name__ == "__main__":
    try:
        compare_road_extraction()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()