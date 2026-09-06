import socket

import httpx
import pytest
import respx

from enricher.fetch import MAX_BYTES, fetch_html
from enricher.safe_url import UnsafeUrlError
from tests.test_safe_url import fake_resolver


@pytest.fixture(autouse=True)
def public_dns(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(socket, "getaddrinfo", fake_resolver("93.184.216.34"))


@respx.mock
async def test_fetches_html() -> None:
    respx.get("https://example.com/a").mock(
        return_value=httpx.Response(
            200, headers={"content-type": "text/html"}, text="<title>t</title>"
        )
    )
    assert "<title>t</title>" in await fetch_html("https://example.com/a")


@respx.mock
async def test_rejects_non_html() -> None:
    respx.get("https://example.com/img").mock(
        return_value=httpx.Response(200, headers={"content-type": "image/png"}, content=b"x")
    )
    with pytest.raises(UnsafeUrlError, match="content-type"):
        await fetch_html("https://example.com/img")


@respx.mock
async def test_rejects_oversized_body() -> None:
    respx.get("https://example.com/big").mock(
        return_value=httpx.Response(
            200, headers={"content-type": "text/html"}, content=b"a" * (MAX_BYTES + 1)
        )
    )
    with pytest.raises(UnsafeUrlError, match="too large"):
        await fetch_html("https://example.com/big")


@respx.mock
async def test_revalidates_redirect_target(monkeypatch: pytest.MonkeyPatch) -> None:
    # 公開ホストが内部ホストへリダイレクトする(典型的な SSRF 迂回)。リダイレクト先で拒否されること。
    respx.get("https://example.com/r").mock(
        return_value=httpx.Response(302, headers={"location": "http://169.254.169.254/latest"})
    )
    calls: list[str] = []

    def resolver(
        host: str, *_a: object, **_k: object
    ) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        calls.append(host)
        ip = "169.254.169.254" if host == "169.254.169.254" else "93.184.216.34"
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (ip, 80))]

    monkeypatch.setattr(socket, "getaddrinfo", resolver)
    with pytest.raises(UnsafeUrlError, match="non-public"):
        await fetch_html("https://example.com/r")
    assert calls == ["example.com", "169.254.169.254"]
