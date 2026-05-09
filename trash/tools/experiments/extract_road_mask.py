#!/usr/bin/env python3
"""
Extract roads from satellite imagery by creating a road mask.
This removes white/background areas and keeps only the road pixels.
"""

import cv2
import numpy as np
from PIL import Image
import json

def create_road_mask(input_image_path, output_mask_path, output_data_path):
    """
    Create a road mask from satellite imagery and extract path data.
    
    Args:
        input_image_path: Path to the satellite map image
        output_mask_path: Path to save the road mask PNG
        output_data_path: Path to save the road pixel coordinates JSON
    """
    
    # Load the image
    img = cv2.imread(input_image_path)
    if img is None:
        raise FileNotFoundError(f"Could not load image: {input_image_path}")
    
    print(f"Loaded image: {img.shape}")
    
    # Convert BGR to RGB
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    
    # Convert to HSV for better color filtering
    img_hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    
    # Define what we consider "white" or background (high saturation means colored)
    # We want to keep areas that are NOT white/light colored
    lower_white = np.array([0, 0, 200])  # Low saturation, high value = white/light
    upper_white = np.array([180, 30, 255])  # Any hue, low saturation, high value
    
    # Create mask for white/background areas
    white_mask = cv2.inRange(img_hsv, lower_white, upper_white)
    
    # Invert to get non-white areas (roads, buildings, etc.)
    road_mask = cv2.bitwise_not(white_mask)
    
    # Apply morphological operations to clean up the mask
    kernel = np.ones((3,3), np.uint8)
    road_mask = cv2.morphologyEx(road_mask, cv2.MORPH_CLOSE, kernel)
    road_mask = cv2.morphologyEx(road_mask, cv2.MORPH_OPEN, kernel)
    
    # Create a more sophisticated road detection
    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Detect edges to help identify road boundaries
    edges = cv2.Canny(gray, 50, 150)
    
    # Combine edge detection with color filtering
    combined_mask = cv2.bitwise_or(road_mask, edges)
    
    # Apply Gaussian blur to soften the mask
    blurred_mask = cv2.GaussianBlur(combined_mask, (5, 5), 0)
    
    # Threshold to get clean binary mask
    _, final_mask = cv2.threshold(blurred_mask, 127, 255, cv2.THRESH_BINARY)
    
    # Save the road mask as PNG
    cv2.imwrite(output_mask_path, final_mask)
    print(f"Saved road mask to: {output_mask_path}")
    
    # Extract coordinates of all road pixels
    road_pixels = []
    height, width = final_mask.shape
    
    # Find all white pixels in the mask (these represent roads)
    road_coords = np.where(final_mask == 255)
    
    print(f"Found {len(road_coords[0])} road pixels")
    
    # Convert to normalized coordinates and sample for efficiency
    sample_rate = max(1, len(road_coords[0]) // 5000)  # Sample to ~5000 points max
    
    for i in range(0, len(road_coords[0]), sample_rate):
        y = road_coords[0][i]
        x = road_coords[1][i]
        
        # Normalize coordinates (0-1 range)
        norm_x = x / float(width)
        norm_y = y / float(height)
        
        road_pixels.append({
            "x": norm_x,
            "y": norm_y,
            "pixel_x": int(x),
            "pixel_y": int(y)
        })
    
    # Save road pixel data
    road_data = {
        "total_pixels": len(road_coords[0]),
        "sampled_pixels": len(road_pixels),
        "image_dimensions": {"width": width, "height": height},
        "road_pixels": road_pixels
    }
    
    with open(output_data_path, 'w') as f:
        json.dump(road_data, f, indent=2)
    
    print(f"Saved road pixel data to: {output_data_path}")
    print(f"Sampled {len(road_pixels)} points from {len(road_coords[0])} total road pixels")
    
    return final_mask, road_pixels

def create_colored_road_overlay(input_image_path, mask_path, output_overlay_path):
    """
    Create a colored road overlay by applying the mask to the original image.
    """
    
    # Load original image and mask
    img = cv2.imread(input_image_path)
    mask = cv2.imread(mask_path, cv2.IMREAD_GRAYSCALE)
    
    if img is None or mask is None:
        raise FileNotFoundError("Could not load input image or mask")
    
    # Create a colored version of just the roads
    road_overlay = np.zeros_like(img)
    
    # Apply mask to original image
    road_overlay[mask == 255] = img[mask == 255]
    
    # Make background transparent (convert to RGBA)
    img_rgba = cv2.cvtColor(road_overlay, cv2.COLOR_BGR2RGBA)
    
    # Set background (black pixels) to transparent
    img_rgba[mask == 0] = [0, 0, 0, 0]  # Transparent background
    
    # Save as PNG with transparency
    cv2.imwrite(output_overlay_path, img_rgba)
    print(f"Saved colored road overlay to: {output_overlay_path}")

if __name__ == "__main__":
    input_image = "map.png"
    mask_output = "data/road_mask.png" 
    data_output = "data/road_pixels.json"
    overlay_output = "data/road_overlay.png"
    
    try:
        # Create output directory
        import os
        os.makedirs("data", exist_ok=True)
        
        print("Creating road mask from satellite imagery...")
        mask, pixels = create_road_mask(input_image, mask_output, data_output)
        
        print("Creating colored road overlay...")
        create_colored_road_overlay(input_image, mask_output, overlay_output)
        
        print("✓ Road extraction complete!")
        print(f"  - Road mask: {mask_output}")
        print(f"  - Road pixels: {data_output} ({len(pixels)} points)")
        print(f"  - Road overlay: {overlay_output}")
        
    except Exception as e:
        print(f"Error: {e}")