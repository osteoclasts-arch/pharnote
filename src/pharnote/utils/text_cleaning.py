from __future__ import annotations

import re
from typing import Iterable, List, Sequence


MOTIVATIONAL_PATTERNS = [
    r"침착",
    r"쫄지",
    r"마인드",
    r"느낌",
    r"감으로",
    r"센스로",
    r"할 수 있다",
    r"포기하지",
]

VAGUE_PATTERNS = [
    r"평가원 느낌",
    r"그냥",
    r"대충",
    r"감각적으로",
    r"흐름을 봐라",
]

ITEM_SPECIFIC_PATTERNS = [
    r"\b20\d{2}\b",
    r"\b(?:q|Q)\d+\b",
    r"\b\d{1,2}번\b",
    r"①|②|③|④|⑤",
    r"정답은?\s*\d",
]

ACTION_VERB_PATTERNS = [
    r"묶",
    r"재정렬",
    r"압축",
    r"고정",
    r"점검",
    r"확인",
    r"검산",
    r"대입",
    r"분리",
    r"비교",
    r"보존",
    r"전환",
    r"선별",
    r"추출",
    r"정리",
]


def compact_whitespace(value: str) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def normalize_for_match(value: str) -> str:
    return re.sub(r"[^0-9a-z가-힣]+", "", compact_whitespace(value).lower())


def split_text_fragments(text: str) -> List[str]:
    normalized = str(text or "").replace("\r\n", "\n")
    fragments: List[str] = []
    for block in re.split(r"\n{2,}", normalized):
        lines = [line.strip(" -•\t") for line in block.splitlines() if line.strip()]
        joined = " ".join(lines)
        for fragment in re.split(r"(?<=[.!?])\s+|;\s+|(?:\s+-\s+)", joined):
            candidate = compact_whitespace(fragment)
            if candidate:
                fragments.append(candidate)
    return fragments


def tokenize(text: str) -> List[str]:
    return [token for token in re.split(r"[^0-9a-z가-힣]+", str(text or "").lower()) if token]


def contains_any_pattern(text: str, patterns: Sequence[str]) -> bool:
    return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns)


def is_motivational_only(text: str) -> bool:
    normalized = compact_whitespace(text)
    if not normalized:
        return True
    has_motivational = contains_any_pattern(normalized, MOTIVATIONAL_PATTERNS)
    has_action = contains_any_pattern(normalized, ACTION_VERB_PATTERNS)
    return has_motivational and not has_action


def is_vague_commentary(text: str) -> bool:
    normalized = compact_whitespace(text)
    if len(normalized) < 12:
        return True
    return contains_any_pattern(normalized, VAGUE_PATTERNS)


def is_item_specific(text: str) -> bool:
    normalized = compact_whitespace(text)
    return contains_any_pattern(normalized, ITEM_SPECIFIC_PATTERNS)


def has_operational_signal(text: str) -> bool:
    normalized = compact_whitespace(text)
    return contains_any_pattern(normalized, ACTION_VERB_PATTERNS) or bool(
        re.search(r"(말고|전에|먼저|기준으로|해야 한다|해라|한다)", normalized)
    )


def extract_evidence_spans(text: str, keywords: Iterable[str]) -> List[str]:
    normalized = compact_whitespace(text)
    spans: List[str] = []
    for keyword in keywords:
        if not keyword:
            continue
        idx = normalized.find(keyword)
        if idx < 0:
            continue
        start = max(0, idx - 18)
        end = min(len(normalized), idx + len(keyword) + 18)
        span = normalized[start:end].strip()
        if span and span not in spans:
            spans.append(span)
    return spans[:4]


def parse_choice_lines(stem_text: str) -> tuple[str, List[str]]:
    text = str(stem_text or "")
    matches = list(re.finditer(r"(①|②|③|④|⑤)", text))
    if len(matches) < 2:
        return compact_whitespace(text), []

    stem = compact_whitespace(text[: matches[0].start()])
    choices: List[str] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        choice = compact_whitespace(text[start:end])
        if choice:
            choices.append(choice)
    return stem, choices


def first_number(value: object) -> int | None:
    if value is None:
        return None
    match = re.search(r"-?\d+", str(value))
    return int(match.group(0)) if match else None
