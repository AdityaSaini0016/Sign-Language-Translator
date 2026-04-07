import cv2
import mediapipe as mp
import numpy as np
import joblib
from collections import deque, Counter
import sqlite3
from datetime import datetime

# --------- TTS (offline) ----------
try:
    import pyttsx3
    tts_engine = pyttsx3.init()
except Exception as e:
    tts_engine = None
    print(f"⚠️ Text-to-Speech not available ({e}). 's' key will be disabled.")

# --------- Load model ----------
artifact = joblib.load('gesture_model.pkl')
gesture_model = artifact['model']
GESTURES = artifact['gestures']   # e.g. ['hello', 'namaste']

# Map gestures to readable text
GESTURE_TO_TEXT = {
    'hello': 'Hello',
    'namaste': 'Namaste',
    'heart': 'I love you', 
    'thankyou': 'Thank you'
}

# --------- Prediction smoothing ----------
PRED_WINDOW = 15          # number of frames in history
STABLE_RATIO = 0.6        # at least 60% same prediction
pred_history = deque(maxlen=PRED_WINDOW)

# --------- Sentence builder ----------
sentence = []

def add_word_from_gesture(gesture_name: str):
    text = GESTURE_TO_TEXT.get(gesture_name, gesture_name)
    if len(sentence) == 0 or sentence[-1] != text:
        sentence.append(text)

def get_sentence() -> str:
    return " ".join(sentence)

def clear_sentence():
    sentence.clear()

def speak_sentence():
    if tts_engine is None:
        print("TTS engine not available.")
        return
    text = get_sentence()
    if not text.strip():
        return
    tts_engine.say(text)
    tts_engine.runAndWait()

# --------- SQLite local DB (fully offline) ----------
DB_NAME = "gestures.db"

def init_db():
    conn = sqlite3.connect(DB_NAME)
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS detections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            gesture TEXT NOT NULL,
            sentence TEXT
        )
    """)
    conn.commit()
    conn.close()

def log_detection(gesture: str, sentence_text: str):
    """
    Log a stable detection into local SQLite DB.
    This stays on the local machine only.
    """
    conn = sqlite3.connect(DB_NAME)
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO detections (timestamp, gesture, sentence) VALUES (?, ?, ?)",
        (datetime.now().isoformat(), gesture, sentence_text)
    )
    conn.commit()
    conn.close()

# Initialize DB
init_db()

# --------- Mediapipe setup ----------
mp_drawing = mp.solutions.drawing_utils
mp_holistic = mp.solutions.holistic

def extract_hand_vector(hand_landmarks) -> np.ndarray:
    """
    Same logic as in collect_data.py:
    - 21 hand landmarks
    - (x, y, z) each
    - relative to wrist
    """
    coords = []
    for lm in hand_landmarks.landmark:
        coords.append([lm.x, lm.y, lm.z])
    coords = np.array(coords)
    base = coords[0].copy()
    coords -= base
    return coords.flatten().reshape(1, -1)  # shape (1, 63)


def get_stable_prediction(new_pred):
    """
    new_pred: int label or None
    Returns stable gesture name or None.
    """
    if new_pred is not None:
        pred_history.append(new_pred)
    else:
        pred_history.append(None)

    # Consider only non-None predictions
    valid_preds = [p for p in pred_history if p is not None]
    if not valid_preds:
        return None

    counts = Counter(valid_preds)
    label, count = counts.most_common(1)[0]

    if count / len(valid_preds) >= STABLE_RATIO:
        return GESTURES[label]
    return None


cap = cv2.VideoCapture(0)

if not cap.isOpened():
    print("❌ Cannot access camera.")
    exit()

last_logged_gesture = None  # to avoid spamming DB & sentence

with mp_holistic.Holistic(
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
) as holistic:

    try:
        while cap.isOpened():
            success, frame = cap.read()
            if not success:
                print("Ignoring empty frame.")
                continue

            frame = cv2.flip(frame, 1)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = holistic.process(rgb)

            # Draw face landmarks (optional, just for visualization)
            if results.face_landmarks:
                mp_drawing.draw_landmarks(
                    frame,
                    results.face_landmarks,
                    mp_holistic.FACEMESH_TESSELATION,
                    landmark_drawing_spec=None,
                    connection_drawing_spec=mp_drawing.DrawingSpec(
                        color=(255, 255, 255),
                        thickness=1,
                        circle_radius=1
                    )
                )

            # Choose one hand to predict from (right preferred, else left)
            hand_landmarks = None
            if results.right_hand_landmarks:
                hand_landmarks = results.right_hand_landmarks
                mp_drawing.draw_landmarks(
                    frame,
                    hand_landmarks,
                    mp_holistic.HAND_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(255, 0, 0), thickness=2, circle_radius=3),
                    mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2)
                )
            elif results.left_hand_landmarks:
                hand_landmarks = results.left_hand_landmarks
                mp_drawing.draw_landmarks(
                    frame,
                    hand_landmarks,
                    mp_holistic.HAND_CONNECTIONS,
                    mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2, circle_radius=3),
                    mp_drawing.DrawingSpec(color=(255, 255, 0), thickness=2)
                )

            raw_label = None
            stable_gesture = None

            if hand_landmarks is not None:
                features = extract_hand_vector(hand_landmarks)
                pred = gesture_model.predict(features)[0]   # integer label
                raw_label = GESTURES[pred]
                stable_gesture = get_stable_prediction(pred)
            else:
                stable_gesture = get_stable_prediction(None)

            # If we have a new stable gesture, update sentence + log to DB
            if stable_gesture is not None and stable_gesture != last_logged_gesture:
                add_word_from_gesture(stable_gesture)
                log_detection(stable_gesture, get_sentence())
                last_logged_gesture = stable_gesture

            # Display info
            raw_text = raw_label.title() if raw_label is not None else "-"
            stable_text = stable_gesture.title() if stable_gesture is not None else "-"

            cv2.putText(frame, f'Mode: Translation (Offline)', (10, 25),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2)

            cv2.putText(frame, f'Raw Gesture: {raw_text}',
                        (10, 55), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

            cv2.putText(frame, f'Stable Gesture: {stable_text}',
                        (10, 85), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

            # Show sentence
            sentence_text = get_sentence()

# Choose color (light cyan)
            color = (255, 200, 100)

# Text properties
            font = cv2.FONT_HERSHEY_SIMPLEX
            font_scale = 0.9
            thickness = 2

# Calculate text size
            (text_width, text_height), _ = cv2.getTextSize(sentence_text, font, font_scale, thickness)

# Position: center horizontally, slightly above the bottom
            x = int((frame.shape[1] - text_width) / 2)
            y = frame.shape[0] - 30       # 30 px from bottom

            cv2.putText(frame, sentence_text, (x, y), font, font_scale, color, thickness)

            # Instructions
            instructions = [
                "q: Quit",
                "c: Clear sentence",
                "s: Speak sentence" if tts_engine is not None else "s: Speak sentence (TTS not installed)"
            ]
            y = 150
            for text in instructions:
                cv2.putText(frame, text, (10, y),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1)
                y += 22

            cv2.imshow('Sign Language Translator (Offline)', frame)

            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('c'):
                clear_sentence()
                last_logged_gesture = None  # allow logging again after clear
            elif key == ord('s'):
                speak_sentence()

    except Exception as e:
        print(f"An error occurred: {e}")

    finally:
        cap.release()
        cv2.destroyAllWindows()
