# Sign Language Translator

This project is a presentation-ready sign language demo built with:

- `sign_translator_app/`: Flutter client for Android, iOS, macOS, Windows, Linux, and web scaffolding
- `backend/`: FastAPI inference service using MediaPipe hand landmarks and a trained gesture classifier

## Demo Flow

1. Open the Flutter app on a device or desktop with a camera.
2. Point the camera at a supported hand sign.
3. The app captures frames, sends them to the backend, and shows:
   - current detection
   - model confidence
   - a confirmed phrase that updates only after stable predictions
4. The app can also speak confirmed words aloud.

## Backend Run

```bash
cd backend
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000
```

Health check:

```bash
http://localhost:8000/health
```

## Flutter Run

The Flutter client defaults to the deployed Render API. To target a local backend for demos:

```bash
cd sign_translator_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use your machine IP instead of `127.0.0.1` when testing from a physical phone.

## Presentation Tips

- Keep the backend running before opening the app.
- Use a plain background and bright lighting for better landmark detection.
- Show the phrase builder and text-to-speech controls during the demo to make the app feel complete.
