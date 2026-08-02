#!/usr/bin/env python3
"""Export every readable Codex session associated with one project directory.

The raw JSONL files are copied without editing. User-root sessions additionally
receive a readable Markdown transcript containing user and assistant messages;
tool calls and tool outputs remain available in the raw JSONL copy.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
from pathlib import Path
from typing import Any, Iterable


SCAFFOLDING_PREFIXES = (
    "<environment_context>",
    "<permissions instructions>",
    "<collaboration_mode>",
    "<apps_instructions>",
    "<plugins_instructions>",
    "<skills_instructions>",
    "<recommended_plugins>",
    "# AGENTS.md instructions",
    "## Memory",
)


def same_path(left: str, right: Path) -> bool:
    return os.path.normcase(os.path.abspath(left)) == os.path.normcase(os.path.abspath(right))


def atomic_copy(source: Path, destination: Path) -> int:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".partial")
    with source.open("rb") as source_handle, temporary.open("wb") as destination_handle:
        shutil.copyfileobj(source_handle, destination_handle, length=1024 * 1024)
    os.replace(temporary, destination)
    return destination.stat().st_size


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".partial")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def record_message(payload: dict[str, Any]) -> tuple[str, str] | None:
    if payload.get("type") != "message":
        return None
    role = str(payload.get("role", "")).strip().lower()
    if role not in {"user", "assistant"}:
        return None
    parts: list[str] = []
    attachment_count = 0
    for item in payload.get("content", []):
        if not isinstance(item, dict):
            continue
        item_type = str(item.get("type", ""))
        if item_type in {"input_text", "output_text", "text"}:
            value = str(item.get("text", "")).strip()
            if value:
                parts.append(value)
        elif item_type in {"input_image", "image", "input_audio", "audio"}:
            attachment_count += 1
    if attachment_count:
        parts.append(f"[附件 {attachment_count} 項；原始資料保留於 JSONL]")
    text = "\n\n".join(parts).strip()
    if not text or (role == "user" and text.startswith(SCAFFOLDING_PREFIXES)):
        return None
    return role, text


def readable_messages(source: Path) -> Iterable[tuple[str, str]]:
    with source.open("r", encoding="utf-8", errors="replace") as handle:
        handle.readline()
        for line in handle:
            if '"type":"response_item"' not in line and '"type": "response_item"' not in line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            message = record_message(record.get("payload", {}))
            if message is not None:
                yield message


def title_from_messages(messages: list[tuple[str, str]], session_id: str) -> str:
    for role, text in messages:
        if role == "user":
            first_line = " ".join(text.splitlines()).strip()
            return (first_line[:96] + "…") if len(first_line) > 96 else first_line
    return session_id


def render_transcript(
    meta: dict[str, Any],
    raw_relative_path: Path,
    messages: list[tuple[str, str]],
) -> str:
    session_id = str(meta.get("id") or meta.get("session_id") or "unknown")
    lines = [
        f"# {title_from_messages(messages, session_id)}",
        "",
        f"- Session ID: `{session_id}`",
        f"- Timestamp: `{meta.get('timestamp', '')}`",
        f"- Thread source: `{meta.get('thread_source', '')}`",
        f"- Working directory: `{meta.get('cwd', '')}`",
        f"- Raw JSONL: `{raw_relative_path.as_posix()}`",
        "- 說明：此檔只整理使用者／助理文字；工具呼叫、完整輸出與其他事件保留於原始 JSONL。",
        "",
    ]
    for role, text in messages:
        label = "使用者" if role == "user" else "助理"
        lines.extend([f"## {label}", "", text, ""])
    return "\n".join(lines).rstrip() + "\n"


def export_sessions(sessions_root: Path, project_root: Path, output_root: Path) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    unreadable: list[dict[str, str]] = []
    source_counts: dict[str, int] = {}
    total_bytes = 0

    for source_path in sorted(sessions_root.rglob("*.jsonl")):
        try:
            with source_path.open("r", encoding="utf-8", errors="replace") as handle:
                first_line = handle.readline()
            first_record = json.loads(first_line)
            meta = first_record.get("payload", {})
            if first_record.get("type") != "session_meta":
                continue
            if not same_path(str(meta.get("cwd", "")), project_root):
                continue
        except (OSError, json.JSONDecodeError) as exc:
            unreadable.append({"path": str(source_path), "error": str(exc)})
            continue

        source = str(meta.get("thread_source") or "unknown")
        relative_source_path = source_path.relative_to(sessions_root)
        raw_relative_path = Path("raw") / source / relative_source_path
        raw_destination = output_root / raw_relative_path
        copied_bytes = atomic_copy(source_path, raw_destination)
        total_bytes += copied_bytes
        source_counts[source] = source_counts.get(source, 0) + 1

        session_id = str(meta.get("id") or meta.get("session_id") or source_path.stem)
        transcript_relative_path: str | None = None
        title = session_id
        message_count = 0
        if source == "user":
            messages = list(readable_messages(source_path))
            message_count = len(messages)
            title = title_from_messages(messages, session_id)
            transcript_path = output_root / "readable" / f"{session_id}.md"
            transcript_relative_path = str(transcript_path.relative_to(output_root)).replace("\\", "/")
            write_text(transcript_path, render_transcript(meta, raw_relative_path, messages))

        rows.append(
            {
                "session_id": session_id,
                "thread_source": source,
                "timestamp": str(meta.get("timestamp", "")),
                "cwd": str(meta.get("cwd", "")),
                "originator": str(meta.get("originator", "")),
                "agent_path": str(meta.get("agent_path", "")),
                "title_from_first_user_message": title,
                "readable_message_count": message_count,
                "raw_bytes": copied_bytes,
                "raw_path": str(raw_relative_path).replace("\\", "/"),
                "readable_transcript": transcript_relative_path,
            }
        )

    manifest = {
        "schema_version": 1,
        "project_root": str(project_root.resolve()),
        "sessions_root": str(sessions_root.resolve()),
        "output_root": str(output_root.resolve()),
        "session_counts": dict(sorted(source_counts.items())),
        "session_total": len(rows),
        "raw_bytes_total": total_bytes,
        "unreadable_count": len(unreadable),
        "unreadable": unreadable,
        "sessions": sorted(rows, key=lambda row: (row["thread_source"], row["timestamp"], row["session_id"])),
    }
    write_text(output_root / "CHAT_EXPORT_MANIFEST.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")

    index_lines = [
        "# 專案聊天匯出索引",
        "",
        f"- 專案：`{project_root.resolve()}`",
        f"- 匯出 session：{len(rows)}",
        f"- 使用者主 chat：{source_counts.get('user', 0)}",
        f"- Subagent chat：{source_counts.get('subagent', 0)}",
        f"- 原始 JSONL bytes：{total_bytes}",
        f"- 不可讀：{len(unreadable)}",
        "- 原始 JSONL 為完整機器可讀匯出；`readable/` 為主 chat 的文字版。",
        "",
        "## 使用者主 chat",
        "",
        "| Timestamp | Session ID | 標題（取第一個實質使用者訊息） | 文字版 |",
        "| --- | --- | --- | --- |",
    ]
    for row in sorted((item for item in rows if item["thread_source"] == "user"), key=lambda item: item["timestamp"]):
        safe_title = str(row["title_from_first_user_message"]).replace("|", "\\|").replace("\n", " ")
        readable = row["readable_transcript"] or ""
        index_lines.append(
            f"| `{row['timestamp']}` | `{row['session_id']}` | {safe_title} | [{row['session_id']}]({readable}) |"
        )
    index_lines.extend(
        [
            "",
            "## 原始資料結構",
            "",
            "- `raw/user/`：使用者主 chats，保留工具呼叫與輸出。",
            "- `raw/subagent/`：所有可讀 subagent chats。",
            "- `CHAT_EXPORT_MANIFEST.json`：逐 session 路徑、大小與來源索引。",
        ]
    )
    write_text(output_root / "CHAT_INDEX.md", "\n".join(index_lines) + "\n")
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sessions-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if not args.sessions_root.is_dir():
        print(f"Sessions root does not exist: {args.sessions_root}")
        return 2
    if not args.project_root.is_dir():
        print(f"Project root does not exist: {args.project_root}")
        return 2
    manifest = export_sessions(args.sessions_root, args.project_root, args.output_root)
    print(json.dumps({key: manifest[key] for key in ("session_counts", "session_total", "raw_bytes_total", "unreadable_count")}, ensure_ascii=False, indent=2))
    return 0 if manifest["unreadable_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
