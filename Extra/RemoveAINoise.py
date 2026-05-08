import cv2
import os
import numpy as np


def remove_pattern_noise(input_path, output_path):
    """
    Removes greenish diagonal color noise by separating the image into
    Lightness and Color channels (LAB space) and smoothing only the color.
    """
    print(f"Loading image from: {input_path}")

    # Check if file exists
    if not os.path.exists(input_path):
        print(f"Error: Could not find the file '{input_path}'.")
        print("Please ensure the script and the image are in the same folder.")
        return

    # Load the image
    img = cv2.imread(input_path)

    if img is None:
        print("Error: Failed to load the image. It might be corrupted.")
        return

    print("Processing image to target greenish color lines...")

    # 1. Convert to LAB color space
    # LAB separates Lightness (L) from color information (A: Green/Red, B: Blue/Yellow)
    # This allows us to blur the color lines without blurring the texture's structural details
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)

    # 2. Aggressively smooth the color channels (A and B)
    # The green lines are primarily in the 'A' channel.
    # A strong median blur destroys the grid pattern in the color data but keeps sharp color boundaries.
    color_kernel_size = (
        15  # Must be an odd number. Increase if color lines are still visible.
    )
    a_smoothed = cv2.medianBlur(a, color_kernel_size)
    b_smoothed = cv2.medianBlur(b, color_kernel_size)

    # 3. Lightly filter the Lightness channel
    # We use a Bilateral Filter, which is famous for keeping edges perfectly sharp
    # while smoothing out subtle noise in flat areas.
    l_smoothed = cv2.bilateralFilter(l, d=5, sigmaColor=25, sigmaSpace=25)

    # 4. Merge the cleaned channels back together
    lab_cleaned = cv2.merge((l_smoothed, a_smoothed, b_smoothed))

    # 5. Convert back to standard BGR color space for saving
    denoised_img = cv2.cvtColor(lab_cleaned, cv2.COLOR_LAB2BGR)

    # Save the cleaned image
    cv2.imwrite(output_path, denoised_img)
    print(f"Success! Cleaned image saved to: {output_path}")


if __name__ == "__main__":
    # The name of the file you uploaded
    INPUT_FILENAME = r"C:\Users\Mary\Downloads\cake tex1.png"
    OUTPUT_FILENAME = r"C:\Users\Mary\Downloads\cake tex2.png"

    remove_pattern_noise(INPUT_FILENAME, OUTPUT_FILENAME)
