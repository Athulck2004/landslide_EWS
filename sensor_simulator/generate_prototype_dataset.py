
from pathlib import Path
import numpy as np
import pandas as pd

# --------------------------------------------------
# 1. SETTINGS
# --------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent
OUTPUT_PATH = BASE_DIR / "Wayanad_Prototype_Training_Data.csv"

N_ROWS = 2500
SEED = 42

rng = np.random.default_rng(SEED)

# --------------------------------------------------
# 2. GENERATE STATIC GIS FEATURES
# All values below are synthetic placeholders.
# They are NOT real measurements from Wayanad.
# --------------------------------------------------

elevation = rng.uniform(620, 2100, N_ROWS)

slope = np.clip(
    rng.gamma(3.0, 8.0, N_ROWS), 2, 62
)

aspect = rng.uniform(0, 360, N_ROWS)

curvature = rng.normal(-0.05, 0.3, N_ROWS)

soil_type = rng.choice(
    ["Laterite", "Gravelly Loam", "Sandy Loam", "Clay"],
    N_ROWS,
)

soil_depth = np.clip(
    rng.normal(1.5, 0.6, N_ROWS)
    - (slope - 20) * 0.008,
    0.3,
    8,
)

lithology = rng.choice(
    ["Charnockite", "Gneiss", "Migmatite"],
    N_ROWS,
)

land_use = rng.choice(
    [
        "Natural Forest",
        "Plantation",
        "Agriculture",
        "Settlement",
        "Scrub",
    ],
    N_ROWS,
)

ndvi_means = {
    "Natural Forest": 0.82,
    "Plantation": 0.65,
    "Agriculture": 0.50,
    "Settlement": 0.30,
    "Scrub": 0.42,
}

ndvi = np.clip(
    np.array([ndvi_means[x] for x in land_use])
    + rng.normal(0, 0.08, N_ROWS),
    0,
    1,
)

distance_to_stream = np.clip(
    rng.exponential(220, N_ROWS),
    5,
    3000,
)

distance_to_road = np.clip(
    rng.exponential(600, N_ROWS),
    10,
    5000,
)

annual_rainfall = np.clip(
    rng.normal(3000, 650, N_ROWS),
    1000,
    4800,
)

past_landslide = rng.binomial(
    1,
    np.clip(0.08 + slope * 0.003, 0.05, 0.35),
    N_ROWS,
)

# --------------------------------------------------
# 3. GENERATE FOUR SIMULATED SENSOR TYPES
# --------------------------------------------------

# Sensor 1: Soil moisture (%)
moisture = np.clip(
    28
    + rng.gamma(2.0, 7.0, N_ROWS)
    + (annual_rainfall - 2500) * 0.006
    + np.where(soil_type == "Clay", 8, 0),
    8,
    98,
)

# Sensor 2: Daily rainfall (mm/day)
daily_rainfall = np.clip(
    rng.gamma(1.8, 12.0, N_ROWS)
    * (annual_rainfall / 3000),
    0,
    420,
)

# Seven-day rainfall is a simulated rolling accumulation,
# not an additional physical sensor.
seven_day_rainfall = np.clip(
    daily_rainfall * rng.uniform(2.0, 4.5, N_ROWS)
    + rng.uniform(0, 80, N_ROWS),
    daily_rainfall,
    1100,
)

# Sensor 3: Pore pressure (kPa)
# Illustrative synthetic values, not physically calibrated.
pore_pressure = np.clip(
    5
    + moisture * 0.25
    + seven_day_rainfall * 0.035
    + soil_depth * 2.0
    + rng.normal(0, 3, N_ROWS),
    0,
    100,
)

# Sensor 4: Tilt change (degrees)
# Generated independently of the risk score to avoid
# directly generating tilt from the target label.
tilt_angle = np.clip(
    rng.gamma(1.5, 0.45, N_ROWS),
    0,
    10,
)

# --------------------------------------------------
# 4. CREATE A SYNTHETIC RISK SCORE
# --------------------------------------------------

# These are demonstration scoring rules only.
# They are NOT validated landslide thresholds.

slope_score = (
    np.clip((slope - 10) / 40, 0, 1) * 20
)

moisture_score = (
    np.clip((moisture - 25) / 65, 0, 1) * 15
)

daily_rain_score = (
    np.clip(daily_rainfall / 150, 0, 1) * 10
)

weekly_rain_score = (
    np.clip(seven_day_rainfall / 500, 0, 1) * 15
)

pore_score = (
    np.clip(pore_pressure / 60, 0, 1) * 15
)

tilt_score = (
    np.clip(tilt_angle / 5, 0, 1) * 15
)

soil_score = np.where(
    np.isin(soil_type, ["Clay", "Laterite"]),
    6,
    0,
)

land_use_score = np.where(
    np.isin(
        land_use,
        ["Plantation", "Agriculture", "Settlement"],
    ),
    5,
    0,
)

history_score = past_landslide * 8

risk_score = (
    slope_score
    + moisture_score
    + daily_rain_score
    + weekly_rain_score
    + pore_score
    + tilt_score
    + soil_score
    + land_use_score
    + history_score
    + rng.normal(0, 3, N_ROWS)
)

# --------------------------------------------------
# 5. ASSIGN THREE CLASSES USING RANK-BASED CUTOFFS
# --------------------------------------------------

# Approximate class proportions:
# Low = 55%, Medium = 28%, High = 17%.
#
# These are intentionally chosen for this synthetic
# prototype. They do NOT represent real-world frequencies.

low_cutoff, high_cutoff = np.quantile(
    risk_score,
    [0.55, 0.83],
)

risk_class = np.select(
    [
        risk_score < low_cutoff,
        risk_score < high_cutoff,
    ],
    [
        0,  # Low
        1,  # Medium
    ],
    default=2,  # High
)

# --------------------------------------------------
# 6. BUILD THE DATASET
# --------------------------------------------------

df = pd.DataFrame({
    "Elevation_m": elevation,
    "Slope_Angle_deg": slope,
    "Aspect_deg": aspect,
    "Curvature": curvature,
    "Soil_Type": soil_type,
    "Soil_Depth_m": soil_depth,
    "Lithology": lithology,
    "Land_Use": land_use,
    "NDVI": ndvi,
    "Distance_to_Stream_m": distance_to_stream,
    "Distance_to_Road_m": distance_to_road,
    "Annual_Rainfall_mm": annual_rainfall,
    "Past_Landslide_Within_1km": past_landslide,
    "Live_Soil_Moisture_Pct": moisture,
    "Live_Daily_Rainfall_mm": daily_rainfall,
    "Live_7Day_Rainfall_mm": seven_day_rainfall,
    "Live_Pore_Pressure_kPa": pore_pressure,
    "Live_Tilt_Angle_deg": tilt_angle,
    "Risk_Class": risk_class,
})

df = df.round(3)

# Save to a NEW filename.
# The original dataset and model are left untouched.
df.to_csv(OUTPUT_PATH, index=False)

# --------------------------------------------------
# 7. VALIDATE AND REPORT
# --------------------------------------------------

print("=" * 55)
print("SYNTHETIC PROTOTYPE DATASET CREATED")
print("=" * 55)

print("File:", OUTPUT_PATH)
print("Dataset size:", df.shape)

print("\nRisk classes (0=Low, 1=Medium, 2=High):")
print(
    df["Risk_Class"]
    .value_counts()
    .sort_index()
)

print("\nClass proportions:")
print(
    df["Risk_Class"]
    .value_counts(normalize=True)
    .sort_index()
    .round(3)
)

print("\nMissing values:", int(df.isnull().sum().sum()))

print("\nFirst three rows:")
print(df.head(3).to_string(index=False))

print("\nIMPORTANT LIMITATIONS:")
print("- Every row is synthetic.")
print("- Risk labels are generated from a hand-designed score.")
print("- Class proportions are deliberately selected.")
print("- Sensor values and scoring rules are not calibrated.")
print("- Model accuracy cannot establish real-world performance.")
