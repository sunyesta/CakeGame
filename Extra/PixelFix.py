import argparse
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from scipy.ndimage import binary_dilation
from pathlib import Path

def fix_pixels(file_path, debug_mode=False):
    try:
        # Open image and ensure it's in RGBA mode
        img = Image.open(file_path).convert("RGBA")
        img_array = np.array(img)

        # Extract the alpha channel
        alpha = img_array[..., 3]

        # Create boolean masks for transparent and opaque pixels
        transparent_mask = (alpha == 0)
        opaque_mask = (alpha != 0)

        # If there are no transparent pixels, skip
        if not np.any(transparent_mask):
            print(f"No transparent pixels to fix in {file_path}")
            return

        # If the image is completely blank, skip
        if not np.any(opaque_mask):
            print(f"Image is entirely transparent: {file_path}")
            return

        # Find the border: Opaque pixels that touch transparent ones (8-neighbor matching)
        # We dilate the transparent mask and intersect it with the opaque mask
        structuring_element = np.ones((3, 3), dtype=bool)
        border_mask = binary_dilation(transparent_mask, structure=structuring_element) & opaque_mask

        # Get coordinates of the opaque border pixels
        y_border, x_border = np.where(border_mask)

        if len(y_border) == 0:
            print(f"No border pixels found in {file_path}")
            return

        # Extract the RGB colors of those border pixels
        border_colors = img_array[y_border, x_border, :3]

        # Build a KD-Tree of the border pixel coordinates for fast spatial queries
        # This replaces the Delaunay/Voronoi logic but achieves the exact same nearest-neighbor result
        tree = cKDTree(np.c_[y_border, x_border])

        # Get coordinates of all fully transparent pixels
        y_trans, x_trans = np.where(transparent_mask)

        # Query the KD-Tree to find the index of the closest border pixel for EVERY transparent pixel
        _, closest_indices = tree.query(np.c_[y_trans, x_trans])

        # Assign the color of the closest border pixel to the transparent pixel's RGB channels
        img_array[y_trans, x_trans, :3] = border_colors[closest_indices]

        # If debug mode is active, set the transparent pixels' alpha to 255 to make the bleed visible
        if debug_mode:
            img_array[y_trans, x_trans, 3] = 255

        # Convert back to a Pillow Image and overwrite the original file
        fixed_img = Image.fromarray(img_array, "RGBA")
        fixed_img.save(file_path)
        print(f"Written to {file_path}")

    except Exception as e:
        print(f"Error processing {file_path}: {e}")

def main():
    parser = argparse.ArgumentParser(
        description="Fix transparent pixels to prevent color bleeding (Pixelfix)",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "paths", 
        nargs="+", 
        help="Path(s) to files or directories.\nIf a directory is passed, all .png files inside will be processed."
    )
    parser.add_argument(
        "-d", "--debug", 
        action="store_true", 
        help="View debug output (will overwrite file with visible alpha layer)"
    )

    args = parser.parse_args()

    files_to_process = []

    # Parse arguments to handle both files and directories
    for path_str in args.paths:
        path = Path(path_str)
        if path.is_file():
            files_to_process.append(path)
        elif path.is_dir():
            # Recursively find all PNG files in the directory
            files_to_process.extend(path.rglob("*.png"))
        else:
            print(f"Invalid path or directory not found: {path}")

    if not files_to_process:
        print("No valid files found to process.")
        return

    # Process all gathered files
    for file in files_to_process:
        fix_pixels(file, args.debug)
        
    print("Finished processing.")

if __name__ == "__main__":
    main()