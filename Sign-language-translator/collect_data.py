import cv2
import mediapipe as mp
import numpy as np
import os
import re

# ---------- CONFIG ----------
GESTURES = ['hello', 'namaste', 'heart','thankyou']   # add: 'heart', 'thankyou', etc later
CURRENT_GESTURE = 'thankyou'       # <-- change this when collecting
DATA_DIR = 'data'
# -----------------------------

if CURRENT_GESTURE not in GESTURES:
    raise ValueError(f"{CURRENT_GESTURE} not in GESTURES list: {GESTURES}")

# Create directories for all gestures
for gesture in GESTURES:
    os.makedirs(os.path.join(DATA_DIR, gesture), exist_ok=True)

# Mediapipe Hands
mp_hands = mp.solutions.hands
mp_drawing = mp.solutions.drawing_utils

hands = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=1,
    min_detection_confidence=0.5
)


def get_next_index(gesture_folder: str) -> int:
    """
    Find the next frame index by looking at existing files.
    Files are named like frame_123.txt
    """
    files = os.listdir(gesture_folder)
    pattern = re.compile(r"frame_(\d+)\.txt")
    indices = []
    for f in files:
        m = pattern.match(f)
        if m:
            indices.append(int(m.group(1)))
    return max(indices) + 1 if indices else 0


def extract_hand_vector(hand_landmarks) -> np.ndarray:
    """
    Convert Mediapipe hand landmarks to a 1D numpy vector:
    - 21 points
    - each with (x, y, z)
    - all points made relative to the wrist (landmark 0)
    """
    coords = []
    for lm in hand_landmarks.landmark:
        coords.append([lm.x, lm.y, lm.z])
    coords = np.array(coords)  # shape: (21, 3)

    # Make them relative to wrist (index 0)
    base = coords[0].copy()
    coords -= base

    return coords.flatten()  # shape: (63,)


gesture_folder = os.path.join(DATA_DIR, CURRENT_GESTURE)
count = get_next_index(gesture_folder)

print(f"Collecting data for gesture: {CURRENT_GESTURE}")
print("Press 'q' to quit.")

cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("❌ Cannot access camera.")
    exit()

while cap.isOpened():
    success, frame = cap.read()
    if not success:
        print("Ignoring empty frame.")
        continue

    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = hands.process(rgb)

    if results.multi_hand_landmarks:
        for hand_landmarks in results.multi_hand_landmarks:
            mp_drawing.draw_landmarks(frame, hand_landmarks, mp_hands.HAND_CONNECTIONS)

            vec = extract_hand_vector(hand_landmarks)
            filepath = os.path.join(gesture_folder, f"frame_{count}.txt")
            np.savetxt(filepath, vec)
            count += 1
            print(f"Saved frame {count} for gesture '{CURRENT_GESTURE}'.")

    cv2.putText(frame, f"Gesture: {CURRENT_GESTURE}", (10, 40),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)

    cv2.imshow('Collecting Data', frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
print(f"Data collection for gesture '{CURRENT_GESTURE}' completed.")
