import os
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH = os.path.join(BASE_DIR, "Wayanad_Prototype_Training_Data.csv")
MODEL_PATH = os.path.join(BASE_DIR, "landslide_rf_model_v2.joblib")

print("Loading prototype dataset...")
df = pd.read_csv(DATASET_PATH)

TARGET = "Risk_Class"

X = df.drop(columns=[TARGET])
y = df[TARGET]

categorical_columns = X.select_dtypes(include=["object", "category", "bool"]).columns.tolist()
numeric_columns = X.select_dtypes(include=["number"]).columns.tolist()

from sklearn.impute import SimpleImputer

preprocessor = ColumnTransformer(
    transformers=[
        ("numeric", SimpleImputer(strategy="median"), numeric_columns),
        (
            "categorical",
            Pipeline([
                ("imputer", SimpleImputer(strategy="most_frequent")),
                ("encoder", OneHotEncoder(handle_unknown="ignore")),
            ]),
            categorical_columns,
        ),
    ]
)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42, stratify=y
)

model = Pipeline([
    ("preprocessor", preprocessor),
    (
        "classifier",
        RandomForestClassifier(
            n_estimators=200,
            random_state=42,
            class_weight="balanced",
            n_jobs=-1,
        ),
    ),
])

print("Training Random Forest on prototype data...")
model.fit(X_train, y_train)

predictions = model.predict(X_test)

print("\n--- Prototype Model V2 Evaluation ---")
print(f"Training rows: {len(X_train)}")
print(f"Testing rows: {len(X_test)}")
print(f"Features used: {X.shape[1]}")

print("\nTest accuracy:", round(accuracy_score(y_test, predictions), 4))

print("\nClassification report (Precision, Recall, F1):")
print(
    classification_report(
        y_test,
        predictions,
        labels=[0, 1, 2],
        target_names=["Low", "Medium", "High"],
        zero_division=0,
    )
)

print("\nConfusion matrix (rows=actual, columns=predicted):")
print(confusion_matrix(y_test, predictions, labels=[0, 1, 2]))

joblib.dump(model, MODEL_PATH)

print("\nModel saved successfully to:", MODEL_PATH)
print("DISCLAIMER: This model was trained on synthetic data for demonstration purposes only.")
print("It does not validate real-world landslide prediction capabilities.")