from enricher.og import parse_page_meta

FULL = """
<html><head>
<title>Fallback Title</title>
<meta name="description" content="plain description">
<meta property="og:title" content="OG Title">
<meta property="og:description" content="OG description">
<meta property="og:image" content="https://example.com/i.png">
<meta property="og:site_name" content="Example">
</head><body><meta property="og:title" content="should be ignored"></body></html>
"""


def test_prefers_og_over_title_and_description() -> None:
    meta = parse_page_meta(FULL)
    assert meta.title == "OG Title"
    assert meta.description == "OG description"
    assert meta.image == "https://example.com/i.png"
    assert meta.site_name == "Example"


def test_ignores_meta_tags_in_body() -> None:
    assert parse_page_meta(FULL).raw_og["og:title"] == "OG Title"


def test_falls_back_to_title_and_description() -> None:
    html = "<head><title> Only  Title </title><meta name=description content=d></head>"
    meta = parse_page_meta(html)
    assert meta.title == "Only  Title"
    assert meta.description == "d"
    assert meta.image is None


def test_empty_document() -> None:
    meta = parse_page_meta("")
    assert meta.title is None
    assert meta.raw_og == {}


def test_first_occurrence_wins() -> None:
    html = (
        '<head><meta property="og:title" content="first">'
        '<meta property="og:title" content="second"></head>'
    )
    assert parse_page_meta(html).title == "first"
