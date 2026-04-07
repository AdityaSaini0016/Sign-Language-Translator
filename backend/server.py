from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
import cv2

from detector import predict_from_frame

app = FastAPI()

# ✅ allow Flutter / emulator / browser
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def home():
    return {"message": "Backend running"}


@app.post("/translate")
async def translate(file: UploadFile = File(...)):

    contents = await file.read()

    npimg = np.frombuffer(contents, np.uint8)

    frame = cv2.imdecode(npimg, cv2.IMREAD_COLOR)

    if frame is None:
        return {"text": "Invalid image"}

    result = predict_from_frame(frame)

    return {"text": str(result)}