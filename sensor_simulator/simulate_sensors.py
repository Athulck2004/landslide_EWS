import os
import time
import random
from datetime import datetime, timezone

from dotenv import load_dotenv
from supabase import create_client


# --------------------------------------------------
# 1. LOAD SUPABASE CONFIGURATION
# --------------------------------------------------

# Load .env from the same folder as this Python file
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")

load_dotenv(ENV_PATH)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Supabase configuration is missing. "
        "Check the .env file beside this Python file."
    )

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)


# --------------------------------------------------
# 2. SIMULATION SETTINGS
# --------------------------------------------------

INTERVAL_SECONDS = 3

# Two monitoring nodes with different starting scenarios
NODES = {
    "NODE_01": {"scenario_offset": 0},
    "NODE_02": {"scenario_offset": 1},
}

SCENARIOS = [
    {
        "name": "Normal conditions",
        "moisture": 30.0,
        "tilt_change": 0.3,
        "rainfall_intensity": 2.0,
    },
    {
        "name": "Warning conditions",
        "moisture": 65.0,
        "tilt_change": 1.5,
        "rainfall_intensity": 15.0,
    },
    {
        "name": "Critical test condition",
        "moisture": 75.0,
        "tilt_change": 6.0,
        "rainfall_intensity": 30.0,
    },
]


# --------------------------------------------------
# 3. CALCULATE DEMONSTRATION RISK LEVEL
# --------------------------------------------------

def calculate_risk(moisture, tilt_change, rainfall_intensity):

    # Demonstration rules only.
    # These are NOT validated landslide warning thresholds.

    if tilt_change >= 5.0:
        return "CRITICAL"

    elif moisture >= 60.0 and rainfall_intensity >= 10.0:
        return "WARNING"

    else:
        return "NORMAL"


# --------------------------------------------------
# 4. GENERATE A SENSOR READING
# --------------------------------------------------

def generate_reading(node_id, scenario):

    # Add small random variations to sensor readings

    moisture = round(
        max(
            0.0,
            min(
                100.0,
                scenario["moisture"] + random.uniform(-2.0, 2.0)
            )
        ),
        2
    )

    tilt_change = round(
        max(
            0.0,
            scenario["tilt_change"] + random.uniform(-0.2, 0.2)
        ),
        2
    )

    rainfall_intensity = round(
        max(
            0.0,
            scenario["rainfall_intensity"]
            + random.uniform(-1.0, 1.0)
        ),
        2
    )

    risk_level = calculate_risk(
        moisture,
        tilt_change,
        rainfall_intensity
    )

    return {
        "node_id": node_id,
        "moisture": moisture,
        "tilt_change": tilt_change,
        "rainfall_intensity": rainfall_intensity,
        "risk_level": risk_level,
        "data_source": "simulation",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
    }


# --------------------------------------------------
# 5. UPLOAD READING TO SUPABASE
# --------------------------------------------------

def upload_reading(reading):

    try:
        supabase.table("sensor_readings").insert(
            reading
        ).execute()

        print(f"[{reading['node_id']}] Upload successful!")

        return True

    except Exception as error:
        print(
            f"[{reading['node_id']}] "
            f"Supabase upload failed: {error}"
        )

        print(
            "Check your project URL, API key, table name, "
            "column names, and Row Level Security policies."
        )

        return False


# --------------------------------------------------
# 6. MAIN SIMULATION LOOP
# --------------------------------------------------

def main():

    print("=" * 55)
    print("LANDSLIDE EARLY WARNING SYSTEM")
    print("Multi-node sensor simulation started")
    print("Nodes:", ", ".join(NODES.keys()))
    print(f"Interval: {INTERVAL_SECONDS} seconds per cycle")
    print("Each cycle creates one reading per node.")
    print("Press Ctrl+C to stop.")
    print("=" * 55)

    cycle = 0

    try:
        while True:

            cycle += 1

            print(f"\n--- Simulation cycle {cycle} ---")

            for node_id, node_config in NODES.items():

                # Rotate scenarios for each node
                scenario_index = (
                    cycle - 1 + node_config["scenario_offset"]
                ) % len(SCENARIOS)

                scenario = SCENARIOS[scenario_index]

                reading = generate_reading(
                    node_id,
                    scenario
                )

                print(f"\nNode: {node_id}")
                print(f"Scenario: {scenario['name']}")
                print(f"Time (UTC): {reading['recorded_at']}")
                print(f"Moisture: {reading['moisture']}%")
                print(f"Tilt change: {reading['tilt_change']} degrees")
                print(
                    f"Rainfall intensity: "
                    f"{reading['rainfall_intensity']}"
                )
                print(f"Risk level: {reading['risk_level']}")

                upload_reading(reading)

            # Wait after uploading readings for both nodes
            time.sleep(INTERVAL_SECONDS)

    except KeyboardInterrupt:
        print("\nSimulation stopped by user.")


if __name__ == "__main__":
    main()