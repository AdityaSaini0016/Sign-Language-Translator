import numpy as np
import joblib
import cv2
import os

# Load model safely
model_path = os.path.join(os.path.dirname(__file__), "models", "gesture_model.pkl")
loaded = joblib.load(model_path)

model = loaded["model"]
GESTURES = loaded["gestures"]

# Lazy load mediapipe
mp_hands = None
hands_detector = None

def init_mediapipe():
    global mp_hands, hands_detector

    if mp_hands is None:
        import mediapipe as mp
        mp_hands = mp.solutions.hands

        hands_detector = mp_hands.Hands(
            static_image_mode=True,
            max_num_hands=1,
            min_detection_confidence=0.5,
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
        init_mediapipe()  # ← IMPORTANT

        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        results = hands_detector.process(rgb)

        if not results.multi_hand_landmarks:
            return "No hand"

        hand_landmarks = results.multi_hand_landmarks[0]
        features = extract_hand_vector(hand_landmarks)

        probs = model.predict_proba(features)[0]
        pred = np.argmax(probs)
        confidence = probs[pred]

        return {
            "text": GESTURES[pred],
            "confidence": float(confidence)
        }

    except Exception as e:
        print("ERROR:", e)
        return "Prediction Error"