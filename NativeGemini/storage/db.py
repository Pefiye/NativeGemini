from __future__ import annotations

import sqlite3
from datetime import UTC, datetime, timedelta
from pathlib import Path

from NativeGemini.config import config_dir
from NativeGemini.storage.models import Conversation, Message


def now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


class Database:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or config_dir() / "nativegemini.sqlite3"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(self.path)
        self.connection.row_factory = sqlite3.Row
        self.migrate()

    def close(self) -> None:
        self.connection.close()

    def migrate(self) -> None:
        self.connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY,
                conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK(role IN ('user','assistant')),
                content TEXT NOT NULL,
                emotion TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS usage_events (
                id INTEGER PRIMARY KEY,
                created_at TEXT NOT NULL,
                model TEXT NOT NULL,
                conversation_id INTEGER,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                grounded INTEGER NOT NULL,
                tavily_searches INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_usage_events_created_at
                ON usage_events(created_at);
            """
        )
        self.connection.commit()

    def create_conversation(self, title: str) -> Conversation:
        cur = self.connection.execute(
            "INSERT INTO conversations (title, created_at) VALUES (?, ?)",
            (title, now_iso()),
        )
        self.connection.commit()
        return self.get_conversation(int(cur.lastrowid))

    def get_conversation(self, conversation_id: int) -> Conversation:
        row = self.connection.execute(
            "SELECT id, title, created_at FROM conversations WHERE id = ?",
            (conversation_id,),
        ).fetchone()
        if row is None:
            raise KeyError(f"Conversation not found: {conversation_id}")
        return Conversation(**dict(row))

    def list_conversations(self) -> list[Conversation]:
        rows = self.connection.execute(
            "SELECT id, title, created_at FROM conversations ORDER BY id DESC"
        ).fetchall()
        return [Conversation(**dict(row)) for row in rows]

    def search_conversations(self, query: str) -> list[Conversation]:
        term = query.strip().lower()
        if not term:
            return self.list_conversations()
        like_term = f"%{term}%"
        rows = self.connection.execute(
            """
            SELECT DISTINCT c.id, c.title, c.created_at
            FROM conversations c
            LEFT JOIN messages m ON m.conversation_id = c.id
            WHERE lower(c.title) LIKE ? OR lower(m.content) LIKE ?
            ORDER BY c.id DESC
            """,
            (like_term, like_term),
        ).fetchall()
        return [Conversation(**dict(row)) for row in rows]

    def rename_conversation(self, conversation_id: int, title: str) -> None:
        self.connection.execute(
            "UPDATE conversations SET title = ? WHERE id = ?",
            (title.strip() or "Untitled", conversation_id),
        )
        self.connection.commit()

    def delete_conversation(self, conversation_id: int) -> None:
        self.connection.execute("DELETE FROM messages WHERE conversation_id = ?", (conversation_id,))
        self.connection.execute("DELETE FROM conversations WHERE id = ?", (conversation_id,))
        self.connection.commit()

    def add_message(self, conversation_id: int, role: str, content: str, emotion: str | None = None) -> Message:
        cur = self.connection.execute(
            """
            INSERT INTO messages (conversation_id, role, content, emotion, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (conversation_id, role, content, emotion, now_iso()),
        )
        self.connection.commit()
        return self.get_message(int(cur.lastrowid))

    def get_message(self, message_id: int) -> Message:
        row = self.connection.execute(
            """
            SELECT id, conversation_id, role, content, emotion, created_at
            FROM messages WHERE id = ?
            """,
            (message_id,),
        ).fetchone()
        if row is None:
            raise KeyError(f"Message not found: {message_id}")
        return Message(**dict(row))

    def list_messages(self, conversation_id: int) -> list[Message]:
        rows = self.connection.execute(
            """
            SELECT id, conversation_id, role, content, emotion, created_at
            FROM messages WHERE conversation_id = ?
            ORDER BY id ASC
            """,
            (conversation_id,),
        ).fetchall()
        return [Message(**dict(row)) for row in rows]

    def replace_last_prompt(self, conversation_id: int, new_content: str) -> Message:
        rows = self.connection.execute(
            """
            SELECT id, role FROM messages
            WHERE conversation_id = ?
            ORDER BY id DESC
            LIMIT 2
            """,
            (conversation_id,),
        ).fetchall()
        ids_to_delete: list[int] = []
        for row in rows:
            ids_to_delete.append(int(row["id"]))
            if row["role"] == "user":
                break
        if ids_to_delete:
            self.connection.executemany("DELETE FROM messages WHERE id = ?", [(item,) for item in ids_to_delete])
        self.connection.commit()
        return self.add_message(conversation_id, "user", new_content)

    def add_usage_event(
        self,
        model: str,
        conversation_id: int,
        input_tokens: int,
        output_tokens: int,
        grounded: bool,
        tavily_searches: int,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO usage_events (
                created_at, model, conversation_id, input_tokens, output_tokens, grounded, tavily_searches
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                now_iso(),
                model,
                conversation_id or None,
                max(0, int(input_tokens)),
                max(0, int(output_tokens)),
                1 if grounded else 0,
                max(0, int(tavily_searches)),
            ),
        )
        self.connection.commit()

    def usage_summary(self, now: datetime | None = None) -> dict[str, int]:
        current_local = now.astimezone() if now else datetime.now().astimezone()
        current_utc = current_local.astimezone(UTC)
        today_start = current_local.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(UTC)
        windows = {
            "today": today_start,
            "day": current_utc - timedelta(days=1),
            "week": current_utc - timedelta(days=7),
        }
        summary: dict[str, int] = {}
        for prefix, start in windows.items():
            row = self.connection.execute(
                """
                SELECT
                    COUNT(*) AS requests,
                    COALESCE(SUM(input_tokens), 0) AS input_tokens,
                    COALESCE(SUM(output_tokens), 0) AS output_tokens,
                    COALESCE(SUM(grounded), 0) AS grounded,
                    COALESCE(SUM(tavily_searches), 0) AS tavily_searches
                FROM usage_events
                WHERE created_at >= ?
                """,
                (start.isoformat(timespec="seconds"),),
            ).fetchone()
            summary[f"{prefix}Requests"] = int(row["requests"])
            summary[f"{prefix}InputTokens"] = int(row["input_tokens"])
            summary[f"{prefix}OutputTokens"] = int(row["output_tokens"])
            summary[f"{prefix}Grounded"] = int(row["grounded"])
            summary[f"{prefix}TavilySearches"] = int(row["tavily_searches"])
            summary[f"{prefix}TotalTokens"] = summary[f"{prefix}InputTokens"] + summary[f"{prefix}OutputTokens"]
        return summary


def title_from_prompt(prompt: str) -> str:
    words = prompt.strip().split()
    if not words:
        return "Untitled"
    return " ".join(words[:6])
