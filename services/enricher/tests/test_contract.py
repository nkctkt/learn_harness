# pyright: reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false
# 理由: starlette.testclient と jsonschema の型情報が部分的(Any を含む)なため。
# テスト対象(enricher)の型安全性には影響しない。
"""契約テスト(producer 側)。

api が期待する応答の形(contracts/*.schema.json、api の zod から生成)で /enrich の応答を検証する。
"""

import json
import socket
from pathlib import Path
from typing import Any

import httpx
import jsonschema
import pytest
import respx
from fastapi.testclient import TestClient

from enricher.main import app
from tests.test_safe_url import fake_resolver

CONTRACT = (
    Path(__file__).resolve().parents[3] / "contracts" / "enricher.enrich.response.schema.json"
)
HTML = '<head><title>T</title><meta property="og:image" content="https://example.com/i.png"></head>'


@respx.mock
def test_enrich_response_matches_consumer_contract(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(socket, "getaddrinfo", fake_resolver("93.184.216.34"))
    respx.get("https://example.com/a").mock(
        return_value=httpx.Response(200, headers={"content-type": "text/html"}, text=HTML)
    )
    schema: dict[str, Any] = json.loads(CONTRACT.read_text())
    with TestClient(app) as client:
        res: httpx.Response = client.post("/enrich", json={"url": "https://example.com/a"})
    assert res.status_code == 200
    body: dict[str, Any] = res.json()
    validator = jsonschema.Draft202012Validator(schema)  # pyright: ignore[reportUnknownMemberType]
    validator.validate(body)  # pyright: ignore[reportUnknownMemberType]
