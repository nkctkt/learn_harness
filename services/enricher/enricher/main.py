from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from enricher.fetch import fetch_html
from enricher.og import PageMeta, parse_page_meta
from enricher.safe_url import UnsafeUrlError

app = FastAPI(title="enricher")


class EnrichRequest(BaseModel):
    url: str = Field(min_length=1, max_length=2048)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "enricher"}


@app.post("/enrich")
async def enrich(req: EnrichRequest) -> PageMeta:
    try:
        html = await fetch_html(req.url)
    except UnsafeUrlError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:  # httpx のタイムアウト・HTTP エラー等。詳細は返さない
        raise HTTPException(status_code=502, detail="failed to fetch url") from e
    return parse_page_meta(html)
