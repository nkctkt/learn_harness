import socket
from collections.abc import Callable

import pytest

from enricher.safe_url import UnsafeUrlError, resolve_public_url

Resolver = Callable[..., list[tuple[int, int, int, str, tuple[str, int]]]]


def fake_resolver(*addrs: str) -> Resolver:
    def _resolve(*_args: object, **_kw: object) -> list[tuple[int, int, int, str, tuple[str, int]]]:
        return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (a, 80)) for a in addrs]

    return _resolve


@pytest.fixture
def resolve_to(monkeypatch: pytest.MonkeyPatch) -> Callable[..., None]:
    def _set(*addrs: str) -> None:
        monkeypatch.setattr(socket, "getaddrinfo", fake_resolver(*addrs))

    return _set


def test_accepts_public_host(resolve_to: Callable[..., None]) -> None:
    resolve_to("93.184.216.34")
    target = resolve_public_url("https://example.com/page")
    assert target.port == 443
    assert target.addresses == ("93.184.216.34",)


@pytest.mark.parametrize(
    "addr",
    [
        "127.0.0.1",
        "10.0.0.5",
        "192.168.1.1",
        "172.16.0.1",
        "169.254.169.254",
        "0.0.0.0",
        "::1",
        "fd00::1",
        "::ffff:127.0.0.1",
    ],
)
def test_rejects_non_public_resolution(resolve_to: Callable[..., None], addr: str) -> None:
    resolve_to(addr)
    with pytest.raises(UnsafeUrlError, match="non-public"):
        resolve_public_url("http://evil.example/")


def test_rejects_when_any_address_is_private(resolve_to: Callable[..., None]) -> None:
    # DNS が公開 IP と内部 IP を混ぜて返す(rebinding 系)場合も拒否する
    resolve_to("93.184.216.34", "10.0.0.5")
    with pytest.raises(UnsafeUrlError):
        resolve_public_url("http://mixed.example/")


@pytest.mark.parametrize(
    ("url", "reason"),
    [
        ("ftp://example.com/", "scheme"),
        ("file:///etc/passwd", "scheme"),
        ("http://user:pw@example.com/", "credentials"),
        ("http://example.com:5432/", "port"),
        ("http://db.internal/", "host not allowed"),
        ("http://localhost:8000/", "host not allowed"),
        ("http:///nohost", "host is required"),
    ],
)
def test_rejects_before_resolution(url: str, reason: str) -> None:
    with pytest.raises(UnsafeUrlError, match=reason):
        resolve_public_url(url)
