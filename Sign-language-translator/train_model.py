import numpy as np
import os
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, confusion_matrix, classification_report
import joblib

DATA_DIR = 'data'
GESTURES = ['hello', 'namaste','heart','thankyou']   # must match folders in data/

X, y = [], []

for label, gesture in enumerate(GESTURES):
    gesture_folder = os.path.join(DATA_DIR, gesture)
    if not os.path.isdir(gesture_folder):
        print(f"⚠️ Folder not found for gesture '{gesture}', skipping.")
        continue

    files = [f for f in os.listdir(gesture_folder) if f.endswith('.txt')]
    if not files:
        print(f"⚠️ No files found in '{gesture_folder}', skipping.")
        continue

    print(f"Loading {len(files)} samples for gesture '{gesture}'")

    for file in files:
        filepath = os.path.join(gesture_folder, file)
        landmarks = np.loadtxt(filepath)
        X.append(landmarks)
        y.append(label)

X = np.array(X)
y = np.array(y)

print(f"Total samples: {len(X)}")

if len(X) == 0:
    raise RuntimeError("No training data found. Please collect data first.")

# Train/test split
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

# Train model
model = RandomForestClassifier(
    n_estimators=150,
    random_state=42,
    n_jobs=-1
)
model.fit(X_train, y_train)

# Evaluate
y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)
cm = confusion_matrix(y_test, y_pred)
cls_report = classification_report(y_test, y_pred, target_names=GESTURES)

print(f"Model Accuracy: {accuracy * 100:.2f}%")
print("Confusion Matrix:\n", cm)
print("\nClassification Report:\n", cls_report)

# Save metrics to a text file (nice for report/teacher)
with open("training_metrics.txt", "w") as f:
    f.write(f"Accuracy: {accuracy * 100:.2f}%\n\n")
    f.write("Confusion Matrix:\n")
    f.write(str(cm) + "\n\n")
    f.write("Classification Report:\n")
    f.write(cls_report)

# Save model + labels together
artifact = {
    'model': model,
    'gestures': GESTURES
}

joblib.dump(artifact, 'gesture_model.pkl')
print("✅ Model and gesture labels saved as 'gesture_model.pkl'")
print("✅ Training metrics saved to 'training_metrics.txt'")
