#!/usr/bin/env python3
"""
Image Color Quantization & Layer Decomposition
----------------------------------------------
Decomposes an image into K discrete RGBA layers based on dominant colors.
Implements an "edge bleed" (anti-halo) technique to ensure seamless
compositing in tools like Photoshop or GIMP without dark fringes.

Requirements:
    pip install opencv-python numpy scikit-learn
"""

import cv2
import numpy as np
from sklearn.cluster import KMeans
import os
import argparse
from pathlib import Path
import logging

# Configure basic logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def rgb_to_hex(rgb_array):
    """Converts an RGB array/list to a hex color string."""
    return "#{:02x}{:02x}{:02x}".format(
        int(rgb_array[0]), int(rgb_array[1]), int(rgb_array[2])
    )


def decompose_image(
    image_path: str,
    k: int,
    sample_size: int = 100000,
    chunk_size: int = 1000000,
    spatial_radius: int = 11,
    blend: bool = False,
):
    """
    Decomposes an image into K layers based on K-Means color quantization.

    Args:
        image_path (str): Path to the input image.
        k (int): Number of color layers to extract.
        sample_size (int): Number of random pixels to use for K-Means fitting.
        chunk_size (int): Number of pixels to process at a time during prediction (memory management).
        spatial_radius (int): Radius for spatial smoothing to flatten intra-object highlights.
        blend (bool): If True, uses soft alpha blending (inverse distance weighting) to capture gradients.
    """
    # 1. Validation & Setup
    if k <= 0:
        logging.error("K must be a positive integer greater than 0.")
        return False

    if not os.path.isfile(image_path):
        logging.error(f"File not found: {image_path}")
        return False

    try:
        # 2. Load & Pre-process Image
        logging.info(f"Loading image from {image_path}...")
        img_bgr = cv2.imread(image_path)

        if img_bgr is None:
            logging.error(
                "OpenCV failed to load the image. Check if the file is a valid image format."
            )
            return False

        # --- FIX: Intra-object Variance vs. Gradients ---
        # If the user wants to preserve smooth gradients, we MUST disable spatial smoothing,
        # because bilateral filtering is specifically designed to flatten gradients into solid blocks.
        if blend:
            logging.info(
                "Blend mode enabled. Disabling spatial smoothing to preserve original gradients."
            )
            spatial_radius = 0

        if spatial_radius > 0:
            logging.info(
                f"Taking pixel distance into account: Applying spatial smoothing (radius={spatial_radius})..."
            )
            # d is the diameter of each pixel neighborhood.
            img_bgr = cv2.bilateralFilter(
                img_bgr, d=spatial_radius, sigmaColor=50, sigmaSpace=spatial_radius
            )

        img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        img_lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB)
        height, width, channels = img_rgb.shape
        logging.info(f"Image dimensions: {width}x{height} pixels.")

        # Reshape to a flat list of pixels for scikit-learn
        pixels_rgb = img_rgb.reshape((-1, 3))
        pixels_lab = img_lab.reshape((-1, 3))
        total_pixels = pixels_rgb.shape[0]

        # 3. Fit K-Means on a subsample for performance
        logging.info("Extracting unique colors to balance cluster weighting...")
        unique_lab = np.unique(pixels_lab, axis=0)

        logging.info(
            f"Sampling {min(sample_size, len(unique_lab))} unique pixels to fit K-Means model (K={k})..."
        )
        rng = np.random.RandomState(42)
        if len(unique_lab) > sample_size:
            sample_indices = rng.choice(len(unique_lab), sample_size, replace=False)
            pixels_sample = unique_lab[sample_indices]
        else:
            pixels_sample = unique_lab

        # Cluster in LAB space for better perceptual color grouping
        kmeans = KMeans(n_clusters=k, random_state=42, n_init="auto")
        kmeans.fit(pixels_sample)

        # Convert LAB centroids back to RGB for the output layer colors
        centroids_lab = kmeans.cluster_centers_.astype(np.uint8).reshape((k, 1, 3))
        centroids_rgb = cv2.cvtColor(centroids_lab, cv2.COLOR_LAB2RGB).reshape((k, 3))

        # 4. Predict labels/alphas for the full resolution image in chunks to save memory
        logging.info(
            "Applying model to full image (this may take a moment for large images)..."
        )

        if blend:
            alphas = np.zeros((total_pixels, k), dtype=np.uint8)
        else:
            labels = np.zeros(total_pixels, dtype=np.int32)

        for i in range(0, total_pixels, chunk_size):
            end = min(i + chunk_size, total_pixels)
            chunk = pixels_lab[i:end]

            if blend:
                # Get the distance from each pixel to all color centroids
                distances = kmeans.transform(chunk)
                # Inverse Distance Weighting: Closer centroids get exponentially higher weights
                weights = 1.0 / (distances**2 + 1e-6)
                # Normalize weights so they sum to 1.0 (100% opacity total across layers)
                norm_weights = weights / np.sum(weights, axis=1, keepdims=True)
                alphas[i:end] = (norm_weights * 255).astype(np.uint8)
            else:
                # Hard clustering
                labels[i:end] = kmeans.predict(chunk)

        if blend:
            alphas_3d = alphas.reshape((height, width, k))
        else:
            labels_2d = labels.reshape((height, width))

        # 5. Output Directory Preparation
        base_path = Path(image_path)
        out_dir = base_path.parent / f"{base_path.stem}_channels"
        out_dir.mkdir(parents=True, exist_ok=True)
        logging.info(f"Created output directory: {out_dir}")

        # Kernel for color bleeding (Dilation) used only in hard-clustering mode
        bleed_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))

        # 6. Decompose and save layers
        logging.info("Generating and saving discrete RGBA layers...")
        for i in range(k):
            centroid_color = centroids_rgb[i].astype(np.uint8)
            hex_color = rgb_to_hex(centroid_color)

            rgb_layer = np.full_like(img_rgb, centroid_color)

            if blend:
                # -- Soft Gradient Masking --
                mask_255 = alphas_3d[:, :, i]
                # Paste the actual image colors wherever the layer has meaningful opacity
                active_mask = mask_255 > 1
                rgb_layer[active_mask] = img_rgb[active_mask]
            else:
                # -- Hard Clustering & Anti-Halo / Edge Bleed Logic --
                mask_bool = labels_2d == i
                mask_255 = (mask_bool * 255).astype(np.uint8)
                dilated_mask = cv2.dilate(mask_255, bleed_kernel, iterations=1)
                rgb_layer[dilated_mask > 0] = img_rgb[dilated_mask > 0]

            # Combine the base layer with the alpha mask
            rgba_layer = np.dstack((rgb_layer, mask_255))

            # Convert RGBA to BGRA for OpenCV saving
            bgra_layer = cv2.cvtColor(rgba_layer, cv2.COLOR_RGBA2BGRA)

            # Construct filename and save
            out_filename = out_dir / f"cluster_{i}_{hex_color}.png"
            cv2.imwrite(str(out_filename), bgra_layer)
            logging.info(f" -> Saved: {out_filename.name}")

        logging.info(
            "Decomposition complete! The stacked layers will reconstruct the original image."
        )
        return True

    except MemoryError:
        logging.error(
            "MemoryError: The image is too large. Try increasing your system pagefile or reducing the input image size."
        )
        return False
    except Exception as e:
        logging.error(f"An unexpected error occurred: {e}")
        return False


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Decompose an image into K layers based on dominant colors using K-Means."
    )
    parser.add_argument(
        "image_path", type=str, help="Path to the input image file (e.g., input.jpg)."
    )
    parser.add_argument(
        "-k",
        "--clusters",
        type=int,
        default=5,
        help="Number of color layers/clusters to generate (default: 5).",
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=100000,
        help="Number of pixels to sample for model fitting (default: 100,000).",
    )
    parser.add_argument(
        "--spatial-radius",
        type=int,
        default=11,
        help="Spatial radius for flattening highlights. Set to 0 to disable.",
    )
    parser.add_argument(
        "--blend",
        action="store_true",
        help="Use soft alpha blending to capture smooth gradients seamlessly.",
    )

    args = parser.parse_args()

    decompose_image(
        args.image_path,
        args.clusters,
        sample_size=args.sample,
        spatial_radius=args.spatial_radius,
        blend=args.blend,
    )
