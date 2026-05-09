import torch
from PIL import Image
from torchvision import transforms
import numpy as np

def create_grid_from_image(model, image_path, image_size, device, threshold=0.5, invert_mask=True):
    """
    Takes a trained U-Net model and an image file path,
    and returns a binary numpy grid (1=wall, 0=free).
    
    Args:
        model: Trained U-Net model
        image_path: Path to floor plan image
        image_size: Target size for grid (e.g., 256)
        device: torch device (cpu/cuda)
        threshold: Segmentation threshold (0.0-1.0). Lower = more walls detected.
                   Default 0.5. Use 0.3-0.4 for faint walls, 0.6-0.7 for bold walls.
        invert_mask: If True, invert the mask (swap wall/free interpretation).
                     Set True for floor plans where rooms appear dark/colored.
                     Set False for floor plans where walls appear dark.
    
    Returns:
        numpy array where 1=wall, 0=free space
    """
    # Load and prepare the model
    model.to(device)
    model.eval()

    # Define the same transformations used during training
    transform = transforms.Compose([
        transforms.Resize((image_size, image_size)),
        transforms.ToTensor(),
    ])

    # Load and transform the input image
    try:
        image = Image.open(image_path).convert("RGB")
        input_tensor = transform(image).unsqueeze(0).to(device)
    except Exception as e:
        print(f"[INFERENCE] Error opening or processing image: {e}")
        return None

    # Get the model prediction
    with torch.no_grad():
        output = model(input_tensor)

    # Process the output into a binary grid
    # Apply sigmoid because our model outputs logits
    output_probs = torch.sigmoid(output)
    
    # Use configurable threshold to decide wall vs. free space
    binary_mask = (output_probs > threshold).float()

    # Squeeze the tensor to remove batch and channel dimensions, move to CPU
    grid_tensor = binary_mask.squeeze().cpu()

    # Convert to NumPy array
    grid_numpy = grid_tensor.numpy()
    
    # MASK INVERSION LOGIC:
    # U-Net outputs 1 for "detected" pixels (typically bright/white areas)
    # Floor plan conventions vary:
    #   - Some: white = walls, colored = rooms → invert_mask=True
    #   - Some: black = walls, white = rooms → invert_mask=False
    # Simulation expects: 1 = walls (blocked), 0 = free space
    if invert_mask:
        grid_numpy = 1 - grid_numpy
        print(f"[INFERENCE] Mask inverted (threshold={threshold}): walls=dark, rooms=bright")
    else:
        print(f"[INFERENCE] Mask NOT inverted (threshold={threshold}): walls=bright, rooms=dark")
    
    # Log grid composition for debugging
    unique, counts = np.unique(grid_numpy, return_counts=True)
    composition = dict(zip(unique.astype(int), counts))
    total = grid_numpy.size
    wall_pct = composition.get(1, 0) / total * 100
    free_pct = composition.get(0, 0) / total * 100
    print(f"[INFERENCE] Grid composition: {wall_pct:.1f}% walls, {free_pct:.1f}% free space")
    
    # Add exterior padding around the grid
    grid_with_padding = add_exterior_padding(grid_numpy, padding_size=20)
    print(f"[INFERENCE] Added 20px exterior padding: {grid_numpy.shape} -> {grid_with_padding.shape}")
    
    return grid_with_padding


def add_exterior_padding(grid, padding_size=20):
    """
    Add exterior padding around the grid for assembly area placement.
    
    Args:
        grid: Original grid (e.g., 256x256) with values 0=free, 1=wall
        padding_size: Pixels of padding on each side (default 20)
    
    Returns:
        Expanded grid (e.g., 296x296) with exterior zone marked as value 4.
        Cell values:
            0 = Free space (inside building)
            1 = Wall
            2 = Door
            3 = Window
            4 = EXTERIOR (padding zone - assembly only, fire blocked)
    """
    original_size = grid.shape[0]
    new_size = original_size + (padding_size * 2)
    
    # Create new grid filled with EXTERIOR marker (4)
    expanded_grid = np.full((new_size, new_size), 4, dtype=np.int32)
    
    # Place original grid in center
    expanded_grid[padding_size:padding_size + original_size,
                  padding_size:padding_size + original_size] = grid.astype(np.int32)
    
    return expanded_grid


def analyze_floor_plan_brightness(image_path, image_size=256):
    """
    Analyze floor plan to auto-detect if mask inversion is needed.
    
    Returns:
        dict with 'should_invert', 'avg_brightness', 'recommendation'
    """
    try:
        image = Image.open(image_path).convert("L")  # Grayscale
        image = image.resize((image_size, image_size))
        pixels = np.array(image)
        
        avg_brightness = np.mean(pixels)
        edge_brightness = np.mean([
            np.mean(pixels[0, :]),   # Top edge
            np.mean(pixels[-1, :]),  # Bottom edge
            np.mean(pixels[:, 0]),   # Left edge
            np.mean(pixels[:, -1])   # Right edge
        ])
        center_brightness = np.mean(pixels[64:192, 64:192])  # Center region
        
        # Heuristic: If edges are brighter than center, rooms are likely bright (invert=True)
        # If edges are darker than center, walls are likely dark (invert=False)
        should_invert = edge_brightness > center_brightness
        
        return {
            "should_invert": should_invert,
            "avg_brightness": float(avg_brightness),
            "edge_brightness": float(edge_brightness),
            "center_brightness": float(center_brightness),
            "recommendation": "invert" if should_invert else "no_invert"
        }
    except Exception as e:
        print(f"[INFERENCE] Error analyzing brightness: {e}")
        return {
            "should_invert": True,  # Default to invert
            "avg_brightness": 128,
            "recommendation": "invert (default)"
        }
