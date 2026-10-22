import os
import time
import pandas as pd
import joblib
from dotenv import load_dotenv
from supabase import create_client

# 1. Setup and Configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, ".env")
MODEL_PATH = os.path.join(BASE_DIR, "landslide_rf_model_v2.joblib")

load_dotenv(ENV_PATH)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError("Supabase configuration is missing. Check the .env file.")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
model = joblib.load(MODEL_PATH)
print("Model loaded successfully.")

# Map database columns to the exact feature names the model expects
FEATURE_MAPPING = {
    "elevation_m": "Elevation_m",
    "slope_angle_deg": "Slope_Angle_deg",
    "aspect_deg": "Aspect_deg",
    "curvature": "Curvature",
    "soil_type": "Soil_Type",
    "soil_depth_m": "Soil_Depth_m",
    "lithology": "Lithology",
    "land_use": "Land_Use",
    "ndvi": "NDVI",
    "distance_to_stream_m": "Distance_to_Stream_m",
    "distance_to_road_m": "Distance_to_Road_m",
    "annual_rainfall_mm": "Annual_Rainfall_mm",
    "past_landslide_within_1km": "Past_Landslide_Within_1km",
    "moisture": "Live_Soil_Moisture_Pct",
    "rainfall_intensity": "Live_Daily_Rainfall_mm",
    "rainfall_7day": "Live_7Day_Rainfall_mm",
    "pore_pressure": "Live_Pore_Pressure_kPa",
    "tilt_change": "Live_Tilt_Angle_deg",
}

def run_prediction(node_id):
    # 2. Fetch latest sensor reading
    sensor_response = supabase.table("sensor_readings").select("*").eq("node_id", node_id).order("recorded_at", desc=True).limit(1).execute()
    if not sensor_response.data:
        print(f"No sensor data found for {node_id}")
        return

    # 3. Fetch static GIS features
    gis_response = supabase.table("node_gis_features").select("*").eq("node_id", node_id).execute()
    if not gis_response.data:
        print(f"No GIS data found for {node_id}")
        return

    sensor_data = sensor_response.data[0]
    gis_data = gis_response.data[0]

    # 4. Merge and map to DataFrame
    combined_data = {**gis_data, **sensor_data}
    model_input = {FEATURE_MAPPING[k]: [v] for k, v in combined_data.items() if k in FEATURE_MAPPING}
    
    df = pd.DataFrame(model_input)

    # 5. Run Prediction
    predicted_class = int(model.predict(df)[0])
    probabilities = model.predict_proba(df)[0]
    confidence = float(max(probabilities))
    
    risk_mapping = {0: "Low", 1: "Medium", 2: "High"}
    predicted_risk = risk_mapping[predicted_class]

    # 6. Save to ml_predictions table
    prediction_record = {
        "node_id": node_id,
        "predicted_class": predicted_class,
        "predicted_risk": predicted_risk,
        "model_confidence": confidence,
        "prediction_source": "synthetic_prototype"
    }
    
    try:
        supabase.table("ml_predictions").insert(prediction_record).execute()
        print(f"[{node_id}] Prediction Saved: {predicted_risk} Risk (Confidence: {confidence:.2f})")
    except Exception as error:
        print(f"[{node_id}] Failed to save prediction: {error}")

def main():
    print("Running Prediction Service continuously. Press Ctrl+C to stop.")
    try:
        while True:
            for node in ["NODE_01", "NODE_02"]:
                try:
                    run_prediction(node)
                except Exception as e:
                    print(f"[{node}] Skipped cycle due to network/API error: {e}")
            
            print("Waiting for next cycle...")
            time.sleep(5) # Runs a new prediction every 5 seconds
            
    except KeyboardInterrupt:
        print("\nPrediction Service stopped by user.")

if __name__ == "__main__":
    main()