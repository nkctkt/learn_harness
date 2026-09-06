"""検証済み URL の取得。タイムアウト・サイズ上限・リダイレクト先の再検証を行う。"""

import httpx

from enricher.safe_url import UnsafeUrlError, resolve_public_url

MAX_BYTES = 1_000_000
MAX_REDIRECTS = 3
TIMEOUT = httpx.Timeout(5.0, connect=3.0)
USER_AGENT = "reading-shelf-enricher/0.1 (+https://github.com/nkctkt/learn_harness)"


async def fetch_html(url: str, client: httpx.AsyncClient | None = None) -> str:
    """公開ホストの HTML を最大 MAX_BYTES まで取得する。リダイレクトは 1 回ずつ再検証する。"""
    own_client = client is None
    client = client or httpx.AsyncClient(timeout=TIMEOUT, follow_redirects=False)
    try:
        current = url
        for _ in range(MAX_REDIRECTS + 1):
            target = resolve_public_url(current)  # リダイレクト先も毎回ここを通す
            async with client.stream("GET", target.url, headers={"user-agent": USER_AGENT}) as res:
                if res.is_redirect:
                    location = res.headers.get("location")
                    if not location:
                        raise UnsafeUrlError("redirect without location")
                    current = str(res.url.join(location))
                    continue
                res.raise_for_status()
                ctype = res.headers.get("content-type", "")
                if "html" not in ctype:
                    raise UnsafeUrlError(f"unsupported content-type: {ctype or '(none)'}")
                chunks: list[bytes] = []
                size = 0
                async for chunk in res.aiter_bytes():
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise UnsafeUrlError("response too large")
                    chunks.append(chunk)
                return b"".join(chunks).decode(res.encoding or "utf-8", errors="replace")
        raise UnsafeUrlError("too many redirects")
    finally:
        if own_client:
            await client.aclose()
