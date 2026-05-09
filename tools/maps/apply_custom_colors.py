import numpy as np
from PIL import Image
import os

def colorize_map(input_path, output_path):
    if not os.path.exists(input_path):
        print(f"Error: {input_path} does not exist.")
        return False
        
    print(f"Applying custom reference colors to {input_path}...")
    img = Image.open(input_path).convert('L')
    arr = np.array(img).astype(float)
    
    # Map the grayscale values of the CartoDB DarkMatter map 
    # to the exact colors from the user's reference image
    
    # x: grayscale value in source image (0-255)
    # y: target RGB colors
    x = [0, 25, 55, 100, 255]
    
    # Target colors based on reference image:
    # 0 (Water) -> #161d29 (22, 29, 41)
    # 25 (Land) -> #222b3c (34, 43, 60)
    # 55 (Minor Roads) -> #3b465c (59, 70, 92)
    # 100 (Major Roads) -> #536380 (83, 99, 128)
    # 255 (Text/Icons) -> #c8d0df (200, 208, 223)
    
    y_r = [22, 34, 59, 83, 200]
    y_g = [29, 43, 70, 99, 208]
    y_b = [41, 60, 92, 128, 223]
    
    # Interpolate
    r = np.interp(arr, x, y_r)
    g = np.interp(arr, x, y_g)
    b = np.interp(arr, x, y_b)
    
    # Stack and save
    out_arr = np.dstack((r, g, b)).astype(np.uint8)
    out_img = Image.fromarray(out_arr)
    out_img.save(output_path)
    print(f"Saved custom colored map to {output_path}")
    return True

if __name__ == "__main__":
    # Use the clean DarkMatter map we generated earlier as the base
    # (Since it is true dark mode, has no harsh halos, and has the correct equal aspect ratio)
    base_map = "assets/maps/map_darkmatter.png"
    out_map = "assets/maps/map.png"
    
    colorize_map(base_map, out_map)
