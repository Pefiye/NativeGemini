from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Conversation:
    id: int
    title: str
    created_at: str


@dataclass(frozen=True)
class Message:
    id: int
    conversation_id: int
    role: str
    content: str
    emotion: str | None
    created_at: str
