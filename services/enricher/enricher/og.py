"""HTML から Open Graph / title を取り出す純粋関数。

ネットワークを触らないのでユニットテストしやすい。
"""

from dataclasses import dataclass, field
from html.parser import HTMLParser


@dataclass
class PageMeta:
    title: str | None = None
    description: str | None = None
    image: str | None = None
    site_name: str | None = None
    raw_og: dict[str, str] = field(default_factory=dict)


class _MetaParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.og: dict[str, str] = {}
        self.title_parts: list[str] = []
        self.description: str | None = None
        self._in_title = False
        self._done_head = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self._done_head:
            return
        if tag == "title":
            self._in_title = True
        elif tag == "meta":
            a = {k.lower(): (v or "") for k, v in attrs}
            prop = a.get("property") or a.get("name") or ""
            content = a.get("content", "")
            if prop.startswith("og:") and content and prop not in self.og:
                self.og[prop] = content
            elif prop == "description" and content and self.description is None:
                self.description = content
        elif tag == "body":
            self._done_head = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
        elif tag == "head":
            self._done_head = True

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self.title_parts.append(data)


def parse_page_meta(html: str) -> PageMeta:
    """<head> 内の og:* と <title> / description を読む。

    og:* を優先し、無ければ <title> にフォールバックする。
    """
    p = _MetaParser()
    p.feed(html)
    p.close()
    title = p.og.get("og:title") or ("".join(p.title_parts).strip() or None)
    return PageMeta(
        title=title,
        description=p.og.get("og:description") or p.description,
        image=p.og.get("og:image"),
        site_name=p.og.get("og:site_name"),
        raw_og=p.og,
    )
