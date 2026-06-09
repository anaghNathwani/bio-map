from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, sightings, annotations, leaderboard, model

app = FastAPI(title="BirdMap API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(sightings.router)
app.include_router(annotations.router)
app.include_router(leaderboard.router)
app.include_router(model.router)


@app.get("/health")
def health():
    return {"status": "ok"}
