"""
Sage/Waggle ML Vision Plugin Template
Updated pattern from yolo-object-counter (June 2025).
Supports four input modes: camera stream, HTTP snapshot, single image, and directory scan.

Customize: model loading, inference, class names, publish topics.
"""
import argparse
import logging
import os
import time
import tempfile
import urllib.request
import urllib.error

import cv2
import numpy as np

from waggle.plugin import Plugin
from waggle.data.vision import Camera

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff", ".webp"}


class Detector:
    def __init__(self, weight_path, conf_thres=0.5, iou_thres=0.45):
        self.conf_thres = conf_thres
        self.iou_thres = iou_thres
        self.model = self._load_model(weight_path)

    def _load_model(self, weight_path):
        """Load your ML model here."""
        # Example for YOLO11:
        # from ultralytics import YOLO
        # model = YOLO(weight_path)
        # return model
        raise NotImplementedError("Replace with your model loading code")

    def run(self, image):
        """
        Run inference on a numpy image (H, W, C) BGR.
        Returns dict of {class_name: count}.
        """
        raise NotImplementedError("Replace with your inference code")


def iter_image_dir(directory):
    """Yield (path, frame, timestamp) for each image in a directory."""
    from pathlib import Path
    files = sorted([
        f for f in Path(directory).iterdir()
        if f.suffix.lower() in IMAGE_EXTENSIONS
        and not f.name.startswith(".")  # skip macOS ._* resource forks
    ])
    if not files:
        raise FileNotFoundError(
            f"No image files found in {directory}. "
            f"Supported extensions: {', '.join(sorted(IMAGE_EXTENSIONS))}"
        )
    logger.info("Found %d test images in %s", len(files), directory)
    for img_path in files:
        frame = cv2.imread(str(img_path))
        if frame is None:
            logger.warning("Skipping unreadable file: %s", img_path.name)
            continue
        yield str(img_path), frame, time.time_ns()


def fetch_snapshot(url: str) -> np.ndarray:
    """
    Fetch a JPEG snapshot from an HTTP URL and return as a BGR numpy array.

    Works with Reolink's HTTP API:
      http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=abc&user=USER&password=CAMERA_PASSWORD

    Also works with any URL that returns a JPEG image.
    """
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            img_bytes = resp.read()
    except urllib.error.URLError as e:
        raise ConnectionError(f"Failed to fetch snapshot from {url}: {e}") from e

    img_array = np.frombuffer(img_bytes, dtype=np.uint8)
    frame = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError(
            f"Could not decode image from {url} "
            f"({len(img_bytes)} bytes received)"
        )
    return frame


def main():
    parser = argparse.ArgumentParser(
        description="ML vision plugin",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Input modes (mutually exclusive, priority: image-dir > snapshot-url > stream):
  --stream <source>       Camera name, RTSP URL, or single image path
  --snapshot-url <url>    HTTP URL returning a JPEG snapshot (e.g. Reolink CGI API)
  --image-dir <path>      Process all images in a directory (sorted)

Examples:
  # Live camera (continuous):
  python app.py --stream bottom_camera --continuous Y

  # HTTP snapshot camera (one-shot test):
  python app.py --snapshot-url "http://IP:PORT/cgi-bin/api.cgi?cmd=Snap&channel=0&rs=snap&user=USER&password=CAMERA_PASSWORD=640&height=360" --continuous N

  # Directory of images (batch):
  python app.py --image-dir ./test-images/ --continuous N
""",
    )
    parser.add_argument("--stream", default="bottom_camera",
                        help="Camera name, RTSP URL, or image path (for testing)")
    parser.add_argument("--image-dir", default=None,
                        help="Process all images in a directory (overrides --stream)")
    parser.add_argument("--snapshot-url", default=None,
                        help="HTTP URL that returns a JPEG snapshot (e.g. Reolink CGI API). "
                             "Overrides --stream. Credentials go in the URL query string.")
    parser.add_argument("--continuous", default="Y",
                        help="Y=loop, N=single-shot")
    parser.add_argument("--interval", type=int, default=30,
                        help="Seconds between captures in continuous mode")
    parser.add_argument("--weight", default="model.pt",
                        help="Path to model weights")
    parser.add_argument("--conf-thres", type=float, default=0.50)
    parser.add_argument("--iou-thres", type=float, default=0.45)
    parser.add_argument("--upload-image", default="Y",
                        help="Y = upload annotated image each cycle")
    args = parser.parse_args()

    using_image_dir = args.image_dir is not None
    using_snapshot_url = args.snapshot_url is not None

    if using_image_dir:
        image_source = iter_image_dir(args.image_dir)
        source_label = f"image-dir:{args.image_dir}"
    elif using_snapshot_url:
        source_label = args.snapshot_url.split("?")[0]  # log URL without query params
    else:
        camera = Camera(args.stream)
        source_label = args.stream

    detector = Detector(args.weight, args.conf_thres, args.iou_thres)

    with Plugin() as plugin:
        logger.info("Plugin started — source=%s, interval=%ds, model=%s",
                     source_label, args.interval, args.weight)

        while True:
            try:
                if using_image_dir:
                    try:
                        img_path, frame, timestamp = next(image_source)
                    except StopIteration:
                        logger.info("All test images processed")
                        break
                    source_name = os.path.basename(img_path)
                    logger.info("Processing: %s (%dx%d)",
                                source_name, frame.shape[1], frame.shape[0])
                elif using_snapshot_url:
                    frame = fetch_snapshot(args.snapshot_url)
                    timestamp = time.time_ns()
                    source_name = "http-snapshot"
                    logger.info("Snapshot: %dx%d from %s",
                                frame.shape[1], frame.shape[0], source_label)
                else:
                    sample = camera.snapshot()
                    frame = sample.data  # numpy BGR
                    timestamp = sample.timestamp
                    source_name = args.stream

                # Run inference
                counts = detector.run(frame)

                # Publish per-class counts
                # PYWAGGLE GOTCHA: every meta value MUST be a str. If you add a
                # field here (confidence, start_time_s, bbox, etc.) wrap it in
                # str() — a float/int/np scalar raises "Meta must be a dictionary
                # of strings to strings" at publish, silently dropping the record
                # (model logs the detection, data API shows nothing). The VALUE
                # arg (here `count`) may be numeric; only meta is string-only.
                for cls_name, count in counts.items():
                    # Sanitize class name for pywaggle topic (a-z0-9_ only)
                    safe_name = cls_name.replace(" ", "_").replace("-", "_")
                    topic = f"env.count.{safe_name}"
                    plugin.publish(
                        topic, count,
                        timestamp=timestamp,
                        meta={"camera": source_name, "model": args.weight},
                    )
                    logger.info("Published %s = %d", topic, count)

                # Self-describing total: includes class breakdown in meta
                classes_summary = ",".join(
                    f"{c}:{n}" for c, n in sorted(counts.items())
                )
                total = sum(counts.values())
                plugin.publish(
                    "env.count.total", total,
                    timestamp=timestamp,
                    meta={
                        "camera": source_name,
                        "model": args.weight,
                        "classes": classes_summary if classes_summary else "none",
                        "num_classes": str(len(counts)),
                    },
                )

                if not counts:
                    logger.info("No detections this cycle")

            except Exception:
                logger.exception("Inference error")

            if args.continuous != "Y" and not using_image_dir:
                break
            if not using_image_dir:
                time.sleep(args.interval)


if __name__ == "__main__":
    main()
