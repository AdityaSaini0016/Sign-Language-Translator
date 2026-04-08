from fastapi import FastAPI, File, UploadFile
import numpy as np
import cv2
from detector import predict_from_frame

app = FastAPI()

@app.post("/translate")
async def translate(file: UploadFile = File(...)):
    try:
        # Read image
        contents = await file.read()
        np_arr = np.frombuffer(contents, np.uint8)
        frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)

        # Call your model
        result = predict_from_frame(frame)

        # If result is dict (with confidence)
        if isinstance(result, dict):
            return result

        # Fallback
        return {"text": result, "confidence": 1.0}

    except Exception as e:
        return {"text": "Error", "confidence": 0.0, "error": str(e)}