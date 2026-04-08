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
        print("Frame received")

        frame = cv2.flip(frame, 1)

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        results = hands_detector.process(rgb)

        if not results.multi_hand_landmarks:
            print("No hand detected")
            return "No hand"

        hand_landmarks = results.multi_hand_landmarks[0]

        if not hand_landmarks:
            print("No hand detected")
            return "No hand"

        features = extract_hand_vector(hand_landmarks)

        print("Feature shape:", features.shape)

        probs = model.predict_proba(features)[0]
        pred = np.argmax(probs)
        confidence = probs[pred]

        print("Prediction:", pred)

        return {
            "text": GESTURES[pred],
            "confidence": float(confidence)
        }

    except Exception as e:
        print("ERROR:", e)
        return "Prediction Error"

