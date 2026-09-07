"""外部 URL を取得する前の SSRF 対策。

「公開ホストか」を文字列ではなく **名前解決後の IP** で判定する。文字列判定だけだと
`http://127.1`、10 進表記、DNS リバインディング、内部ホスト名(`db.internal`)を通してしまう。
"""

import ipaddress
import socket
from dataclasses import dataclass
from urllib.parse import urlsplit

ALLOWED_SCHEMES = frozenset({"http", "https"})
BLOCKED_PORTS = frozenset({22, 25, 3306, 5432, 6379, 9200, 11211})


class UnsafeUrlError(ValueError):
    """取得してはいけない URL。理由をメッセージに持つ。"""


@dataclass(frozen=True)
class ResolvedTarget:
    url: str
    host: str
    port: int
    addresses: tuple[str, ...]


def _is_public_ip(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    return not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
        or (
            isinstance(ip, ipaddress.IPv6Address)
            and ip.ipv4_mapped is not None
            and not _is_public_ip(ip.ipv4_mapped)
        )
    )


def resolve_public_url(url: str) -> ResolvedTarget:
    """スキーム・ポート・解決先 IP を検証し、全て公開アドレスの時だけ返す。"""
    parts = urlsplit(url)
    if parts.scheme not in ALLOWED_SCHEMES:
        raise UnsafeUrlError(f"scheme not allowed: {parts.scheme or '(none)'}")
    if not parts.hostname:
        raise UnsafeUrlError("host is required")
    if parts.username or parts.password:
        raise UnsafeUrlError("credentials in url are not allowed")
    port = parts.port or (443 if parts.scheme == "https" else 80)
    if port in BLOCKED_PORTS:
        raise UnsafeUrlError(f"port not allowed: {port}")
    host = parts.hostname
    if host.endswith((".localhost", ".internal", ".local")) or host == "localhost":
        raise UnsafeUrlError(f"host not allowed: {host}")
    try:
        infos = socket.getaddrinfo(host, port, proto=socket.IPPROTO_TCP)
    except socket.gaierror as e:
        raise UnsafeUrlError(f"cannot resolve host: {host}") from e
    addresses = tuple(sorted({str(info[4][0]) for info in infos}))
    if not addresses:
        raise UnsafeUrlError(f"cannot resolve host: {host}")
    for addr in addresses:
        if not _is_public_ip(ipaddress.ip_address(addr)):
            raise UnsafeUrlError(f"host resolves to a non-public address: {host} -> {addr}")
    return ResolvedTarget(url=url, host=host, port=port, addresses=addresses)
