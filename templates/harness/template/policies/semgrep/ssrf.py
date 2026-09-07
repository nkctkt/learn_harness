import httpx
from fastapi import FastAPI
from pydantic import BaseModel

from enricher.fetch import fetch_html
from enricher.safe_url import resolve_public_url

app = FastAPI()


class Req(BaseModel):
    url: str


@app.post("/bad")
async def bad(req: Req) -> dict[str, int]:
    async with httpx.AsyncClient() as client:
        # ruleid: shelf.py-ssrf-unvalidated-request
        res = await client.get(req.url)
    return {"status": res.status_code}


@app.post("/bad2")
def bad2(req: Req) -> dict[str, int]:
    # ruleid: shelf.py-ssrf-unvalidated-request
    return {"status": httpx.get(req.url).status_code}


@app.post("/good")
async def good(req: Req) -> dict[str, str]:
    # ok: shelf.py-ssrf-unvalidated-request
    return {"html": await fetch_html(req.url)}


@app.post("/good2")
def good2(req: Req) -> dict[str, int]:
    target = resolve_public_url(req.url)
    # ok: shelf.py-ssrf-unvalidated-request
    return {"status": httpx.get(target.url).status_code}
