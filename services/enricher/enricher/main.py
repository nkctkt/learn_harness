from fastapi import FastAPI

app = FastAPI(title="enricher")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "enricher"}
