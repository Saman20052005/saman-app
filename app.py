"""HF Space entrypoint for FastAPI app."""

from backend.main import app


# For Hugging Face Space: this module should export `app` as ASGI application.
# Then the start command can be:
#   uvicorn app:app --host 0.0.0.0 --port $PORT
