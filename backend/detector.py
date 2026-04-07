import mediapipe as mp
import numpy as np
import joblib
import cv2

# Load the trained model (update path if needed)
loaded = joblib.load(r"D:\Sign Language Translator\Sign-language-translator\gesture_model.pkl")

print(type(loaded))      # TEMP
print(loaded.keys())     # TEMP

model = loaded["model"]
GESTURES = loaded["gestures"]

mp_holistic = mp.solutions.holistic  # Correct import

# Initialize detector
holistic_detector = mp_holistic.Holistic(
    static_image_mode=True,
    model_complexity=1,
    min_detection_confidence=0.3,
    min_tracking_confidence=0.3,
)


def extract_hand_vector(hand_landmarks):
    coords = []
    for lm in hand_landmarks.landmark:
        coords.append([lm.x, lm.y, lm.z])
    coords = np.array(coords)
    base = coords[0].copy()
    coords -= base
    return coords.flatten().reshape(1, -1)

def predict_from_frame(frame):

    try:
        print("Frame received")

        frame = cv2.flip(frame, 1)

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        results = holistic_detector.process(rgb)

        hand_landmarks = results.right_hand_landmarks or results.left_hand_landmarks

        if not hand_landmarks:
            print("No hand detected")
            return "No hand"

        features = extract_hand_vector(hand_landmarks)

        print("Feature shape:", features.shape)

        pred = model.predict(features)[0]

        print("Prediction:", pred)

        return GESTURES[pred]

    except Exception as e:
        print("ERROR:", e)
        return "Prediction Error"

