from __future__ import annotations

import os
import re
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx


@dataclass(frozen=True)
class WebSearchResult:
    title: str
    url: str
    snippet: str


class WebSearchUnavailable(RuntimeError):
    pass


def _clean_text(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def parse_tavily_response(payload: dict, limit: int = 6) -> list[WebSearchResult]:
    raw_results = payload.get("results", [])
    if not isinstance(raw_results, list):
        return []
    results: list[WebSearchResult] = []
    seen: set[str] = set()
    for item in raw_results:
        if not isinstance(item, dict):
            continue
        title = _clean_text(item.get("title"))
        url = _clean_text(item.get("url"))
        snippet = _clean_text(item.get("content") or item.get("raw_content"))
        parsed = urlparse(url)
        if not title or parsed.scheme not in {"http", "https"} or not parsed.netloc or url in seen:
            continue
        results.append(WebSearchResult(title, url, snippet))
        seen.add(url)
        if len(results) >= limit:
            break
    return results


def search_web(query: str, api_key: str = "", limit: int = 6) -> list[WebSearchResult]:
    normalized = re.sub(r"\s+", " ", query).strip()[:600]
    tavily_api_key = (api_key or os.environ.get("TAVILY_API_KEY", "")).strip()
    if not normalized:
        return []
    if not tavily_api_key:
        raise WebSearchUnavailable("Tavily API key is not configured.")
    response = httpx.post(
        "https://api.tavily.com/search",
        headers={
            "Authorization": f"Bearer {tavily_api_key}",
            "Content-Type": "application/json",
        },
        json={
            "query": normalized,
            "search_depth": "basic",
            "topic": "general",
            "include_answer": False,
            "include_raw_content": False,
            "max_results": max(1, min(limit, 10)),
        },
        timeout=15,
    )
    response.raise_for_status()
    return parse_tavily_response(response.json(), limit)
