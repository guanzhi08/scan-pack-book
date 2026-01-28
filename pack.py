from PIL import Image, ImageEnhance
import glob
import numpy as np

# ---------- Detect image type ----------
def detect_page_type(
    img,
    sample_step=10,
    rgb_diff_threshold=28,
    color_ratio_threshold=0.12,
    text_white_ratio=0.65,
    text_black_ratio=0.01,
    mid_gray_ratio_max=0.25
):
    """
    Aggressive black and white detection.
    Returns one of:
    - "black_white"
    - "grayscale"
    - "color"
    """

    rgb = img.convert("RGB")
    arr = np.array(rgb)

    sampled = arr[::sample_step, ::sample_step]

    r = sampled[:, :, 0].astype(int)
    g = sampled[:, :, 1].astype(int)
    b = sampled[:, :, 2].astype(int)

    # Color detection (very conservative)
    max_diff = np.maximum.reduce([
        np.abs(r - g),
        np.abs(r - b),
        np.abs(g - b)
    ])

    strong_color = np.sum(max_diff > rgb_diff_threshold)
    total = sampled.shape[0] * sampled.shape[1]

    if (strong_color / total) >= color_ratio_threshold:
        return "color"

    # Grayscale analysis
    gray = rgb.convert("L")
    garr = np.array(gray)[::sample_step, ::sample_step]

    white_ratio = np.mean(garr > 235)
    black_ratio = np.mean(garr < 45)
    mid_ratio = np.mean((garr >= 45) & (garr <= 235))

    # Text-dominant grayscale page
    if (
        white_ratio >= text_white_ratio and
        black_ratio >= text_black_ratio and
        mid_ratio <= mid_gray_ratio_max
    ):
        return "black_white"

    return "grayscale"

# ---------- Main conversion process ----------
def pngs_to_mixed_pdf(
    input_pattern=r"screenshots\*.png",
    # outoput file
    output_pdf="output.pdf",
    dpi=300,
    bw_threshold=180
):
    pngs = sorted(glob.glob(input_pattern))
    pages = []

    for idx, path in enumerate(pngs):
        img = Image.open(path)

        if idx == 0:
            page_type = "color"
        else:
            page_type = detect_page_type(img)

        if page_type == "black_white":
            img = img.convert("L")

            # Very strong contrast for text
            img = ImageEnhance.Contrast(img).enhance(2.6)

            # Slight sharpening to emphasize character edges
            img = ImageEnhance.Sharpness(img).enhance(1.8)

            # Hard binarization
            img = img.point(
                lambda x: 255 if x > 175 else 0,
                mode="1"
            )

            # print(f"Black and white page: {path}")

        elif page_type == "grayscale":
            img = img.convert("L")
            print(f"Grayscale page: {path}")

        else:  # color
            img = img.convert("RGB")
            print(f"Color page: {path}")

        pages.append(img)

    pages[0].save(
        output_pdf,
        save_all=True,
        append_images=pages[1:],
        resolution=dpi
    )

    print(f"\nDone: {output_pdf}")


if __name__ == "__main__":
    pngs_to_mixed_pdf()
