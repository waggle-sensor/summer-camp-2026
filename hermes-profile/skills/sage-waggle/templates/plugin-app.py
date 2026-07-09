"""
Sage/Waggle Edge Plugin Template
Minimal plugin that reads a sensor and publishes data.
Customize the read_sensor() function and measurement name.
"""
import argparse
import logging
import time

from waggle.plugin import Plugin

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def read_sensor():
    """Replace with actual sensor reading logic."""
    # Example: read temperature from BME680
    # import board, adafruit_bme680
    # i2c = board.I2C()
    # sensor = adafruit_bme680.Adafruit_BME680_I2C(i2c)
    # return sensor.temperature
    return 0.0


def main():
    parser = argparse.ArgumentParser(description="Sage edge plugin")
    parser.add_argument("--interval", type=int, default=30, help="Seconds between readings")
    args = parser.parse_args()

    with Plugin() as plugin:
        logger.info("Plugin started, publishing every %d seconds", args.interval)
        while True:
            try:
                value = read_sensor()
                # PYWAGGLE GOTCHA: every value in meta={} MUST be a str.
                # Passing a float/int/np scalar raises at publish time:
                #   TypeError: Meta must be a dictionary of strings to strings.
                # This crashes the publish silently from the data-API's POV
                # (the record never lands). The published VALUE (2nd arg) may be
                # numeric or a JSON string; only meta is string-only. Wrap any
                # non-string meta value in str(): meta={"conf": str(0.97)}.
                plugin.publish(
                    "env.measurement.name",  # Change to your measurement name
                    value,
                    meta={"units": "C", "sensor": "bme680"},  # ALL values must be str
                )
                logger.info("Published: %s", value)
            except Exception as e:
                logger.error("Error reading sensor: %s", e)
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
