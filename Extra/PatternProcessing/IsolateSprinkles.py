import cv2
import numpy as np
import sys
import argparse

# Global variables to hold our images and state for the GUI callbacks
img_with = None
img_without = None
checkerboard_bg = None
output_filepath = ""


def create_checkerboard(h, w, square_size=20):
    """Creates a checkerboard background to visualize transparency."""
    bg = np.zeros((h, w, 3), dtype=np.uint8)
    for y in range(0, h, square_size):
        for x in range(0, w, square_size):
            if (x // square_size + y // square_size) % 2 == 0:
                bg[y : y + square_size, x : x + square_size] = (
                    192,
                    192,
                    192,
                )  # Light Gray
            else:
                bg[y : y + square_size, x : x + square_size] = (255, 255, 255)  # White
    return bg


def process_and_update(*args):
    """Callback function triggered whenever a slider is moved."""
    # 1. Get current positions of trackbars
    threshold_value = cv2.getTrackbarPos("Threshold", "Sprinkle Isolator")

    # OpenCV trackbars only support integers, so we divide by 10 to get floats (e.g., 25 -> 2.5)
    opacity_boost_int = cv2.getTrackbarPos("Opacity Boost", "Sprinkle Isolator")
    opacity_boost = opacity_boost_int / 10.0

    # Get background and color picker trackbars
    bg_mode = cv2.getTrackbarPos("Bg Mode (0=Check, 1=Img)", "Sprinkle Isolator")
    mult_h = cv2.getTrackbarPos("Hue", "Sprinkle Isolator")
    mult_s = cv2.getTrackbarPos("Sat", "Sprinkle Isolator")
    mult_v = cv2.getTrackbarPos("Val", "Sprinkle Isolator")

    # 2. Process the images
    diff = cv2.absdiff(img_with, img_without)
    gray_diff = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)

    _, alpha_mask = cv2.threshold(gray_diff, threshold_value, 255, cv2.THRESH_TOZERO)
    alpha_mask = cv2.convertScaleAbs(alpha_mask, alpha=opacity_boost, beta=0)
    alpha_mask = cv2.GaussianBlur(alpha_mask, (3, 3), 0)

    # 3. Create the preview image (blend the foreground with the background using the alpha mask)
    # Convert alpha mask to 0.0 - 1.0 range and stack it to 3 channels for multiplication
    alpha_normalized = alpha_mask.astype(float) / 255.0
    alpha_3d = np.dstack([alpha_normalized] * 3)

    # Determine which background to use based on the toggle
    if bg_mode == 1:
        # Convert chosen HSV color to BGR for multiplication
        hsv_color = np.uint8([[[mult_h, mult_s, mult_v]]])
        bgr_color = cv2.cvtColor(hsv_color, cv2.COLOR_HSV2BGR)[0][0]
        color_multiplier = np.array(
            [bgr_color[0] / 255.0, bgr_color[1] / 255.0, bgr_color[2] / 255.0]
        )
        current_bg = img_without.astype(float) * color_multiplier
    else:
        current_bg = checkerboard_bg.astype(float)

    # Blend: (Foreground * Alpha) + (Background * (1 - Alpha))
    preview_img = (img_with.astype(float) * alpha_3d) + (current_bg * (1.0 - alpha_3d))
    preview_img = np.clip(preview_img, 0, 255).astype(np.uint8)

    # 4. Show the preview
    cv2.imshow("Sprinkle Isolator", preview_img)

    # Store the final RGBA image in a global variable so we can save it later
    b, g, r = cv2.split(img_with)
    global final_rgba
    final_rgba = cv2.merge((b, g, r, alpha_mask))


def main():
    global img_with, img_without, checkerboard_bg, output_filepath

    # Setup command line argument parsing
    parser = argparse.ArgumentParser(
        description="Interactive GUI to isolate differences between two images."
    )
    parser.add_argument(
        "-w", "--with_sprinkles", required=True, help="Path to the image with sprinkles"
    )
    parser.add_argument(
        "-wo",
        "--without_sprinkles",
        required=True,
        help="Path to the image without sprinkles",
    )
    parser.add_argument(
        "-out",
        "--output",
        default="isolated_sprinkles.png",
        help="Path for the output PNG",
    )
    parser.add_argument(
        "-t",
        "--threshold",
        type=int,
        default=15,
        help="Initial Threshold value (default: 15)",
    )
    parser.add_argument(
        "-ob",
        "--opacity_boost",
        type=float,
        default=2.5,
        help="Initial Opacity boost multiplier (default: 2.5)",
    )
    args = parser.parse_args()

    output_filepath = args.output

    # 1. Load the images
    img_with = cv2.imread(args.with_sprinkles)
    img_without = cv2.imread(args.without_sprinkles)

    if img_with is None or img_without is None:
        print("Error: Could not load one or both images. Check the file paths.")
        sys.exit(1)

    if img_with.shape != img_without.shape:
        print("Error: Images must be the exact same dimensions for differencing.")
        sys.exit(1)

    # Generate checkerboard background matching image size
    h, w = img_with.shape[:2]
    checkerboard_bg = create_checkerboard(h, w)

    # 2. Setup the GUI Window
    cv2.namedWindow("Sprinkle Isolator", cv2.WINDOW_NORMAL)
    # Resize window to fit on screen if the images are massive
    cv2.resizeWindow("Sprinkle Isolator", 800, 800 * h // w)

    # 3. Create Trackbars (sliders)
    # Opacity trackbar goes from 0 to 100 (which we map to 0.0 to 10.0 in the callback)
    initial_opacity_int = int(args.opacity_boost * 10)

    cv2.createTrackbar(
        "Threshold", "Sprinkle Isolator", args.threshold, 255, process_and_update
    )
    cv2.createTrackbar(
        "Opacity Boost",
        "Sprinkle Isolator",
        initial_opacity_int,
        100,
        process_and_update,
    )

    # New trackbars for background toggle and color multiply effect using HSV
    cv2.createTrackbar(
        "Bg Mode (0=Check, 1=Img)", "Sprinkle Isolator", 0, 1, process_and_update
    )
    cv2.createTrackbar("Hue", "Sprinkle Isolator", 0, 179, process_and_update)
    cv2.createTrackbar("Sat", "Sprinkle Isolator", 0, 255, process_and_update)
    cv2.createTrackbar("Val", "Sprinkle Isolator", 255, 255, process_and_update)

    # Run the initial update to show the image right away
    process_and_update()

    print("\n" + "=" * 50)
    print("GUI Loaded!")
    print(" - Adjust Threshold and Opacity to isolate the sprinkles.")
    print(" - Switch 'Bg Mode' to 1 to view with the background image.")
    print(" - Adjust Hue/Sat/Val to multiply color over the background.")
    print(" - Press 's' to SAVE the isolated transparent PNG result and quit.")
    print(" - Press 'q' or 'ESC' to QUIT without saving.")
    print("=" * 50 + "\n")

    # 4. Main loop to catch key presses
    while True:
        key = cv2.waitKey(1) & 0xFF

        # Press 's' to save
        if key == ord("s"):
            cv2.imwrite(output_filepath, final_rgba)
            print(f"Success! Saved smoothly isolated sprinkles to: {output_filepath}")
            break

        # Press 'q' or ESC to exit without saving
        elif key == ord("q") or key == 27:
            print("Exiting without saving.")
            break

    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
