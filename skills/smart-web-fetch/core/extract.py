from __future__ import annotations

import re
from html.parser import HTMLParser


class HTMLTextExtractor(HTMLParser):
    BLOCK_TAGS = {
        "article",
        "aside",
        "blockquote",
        "br",
        "div",
        "footer",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "header",
        "hr",
        "li",
        "main",
        "nav",
        "ol",
        "p",
        "pre",
        "section",
        "table",
        "tr",
        "ul",
    }
    IGNORE_TAGS = {"script", "style", "noscript"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._chunks: list[str] = []
        self._ignore_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in self.IGNORE_TAGS:
            self._ignore_depth += 1
            return
        if self._ignore_depth:
            return
        if tag in self.BLOCK_TAGS:
            self._chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in self.IGNORE_TAGS:
            if self._ignore_depth:
                self._ignore_depth -= 1
            return
        if self._ignore_depth:
            return
        if tag in self.BLOCK_TAGS:
            self._chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self._ignore_depth or not data:
            return
        self._chunks.append(data)

    def get_text(self) -> str:
        text = "".join(self._chunks)
        text = re.sub(r"\r\n?", "\n", text)
        text = re.sub(r"[ \t\f\v]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        lines = [line.strip() for line in text.splitlines()]
        return "\n".join(line for line in lines if line).strip()


def clean_html(html: str) -> str:
    patterns = [
        r"(?is)<script\b[^>]*>.*?</script>",
        r"(?is)<style\b[^>]*>.*?</style>",
        r"(?is)<noscript\b[^>]*>.*?</noscript>",
        r"(?is)<nav\b[^>]*>.*?</nav>",
        r"(?is)<header\b[^>]*>.*?</header>",
        r"(?is)<footer\b[^>]*>.*?</footer>",
        r"(?is)<aside\b[^>]*>.*?</aside>",
        r"(?is)<!--.*?-->",
    ]
    cleaned = html
    for pattern in patterns:
        cleaned = re.sub(pattern, "", cleaned)
    cleaned = re.sub(r'\s(?:class|id|style|on\w+)=(".*?"|\'.*?\')', "", cleaned, flags=re.IGNORECASE | re.DOTALL)
    return cleaned


def html_to_text(html: str) -> str:
    parser = HTMLTextExtractor()
    parser.feed(html)
    parser.close()
    return parser.get_text()


def looks_like_html(text: str, content_type: str) -> bool:
    lowered_type = (content_type or "").lower()
    if "text/html" in lowered_type or "application/xhtml+xml" in lowered_type:
        return True
    lowered_text = text.lower()
    return "<html" in lowered_text or "<body" in lowered_text or "<article" in lowered_text
