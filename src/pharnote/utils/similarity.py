from __future__ import annotations

from difflib import SequenceMatcher
from typing import Iterable, Set

from .text_cleaning import tokenize


def normalized_string_similarity(left: str, right: str) -> float:
    return SequenceMatcher(None, left or "", right or "").ratio()


def token_overlap(left: str, right: str) -> float:
    left_tokens = set(tokenize(left))
    right_tokens = set(tokenize(right))
    if not left_tokens or not right_tokens:
        return 0.0
    intersection = len(left_tokens & right_tokens)
    union = len(left_tokens | right_tokens)
    return intersection / union if union else 0.0


def _extract_focus_terms(text: str) -> Set[str]:
    return {token for token in tokenize(text) if len(token) >= 2}


def verb_object_overlap(left: str, right: str) -> float:
    left_terms = _extract_focus_terms(left)
    right_terms = _extract_focus_terms(right)
    if not left_terms or not right_terms:
        return 0.0
    intersection = len(left_terms & right_terms)
    return (2 * intersection) / (len(left_terms) + len(right_terms))


def weighted_similarity(
    left: str,
    right: str,
    *,
    sequence_weight: float,
    token_weight: float,
    verb_weight: float,
) -> dict:
    sequence_score = normalized_string_similarity(left, right)
    token_score = token_overlap(left, right)
    verb_score = verb_object_overlap(left, right)
    overall = (
        sequence_weight * sequence_score
        + token_weight * token_score
        + verb_weight * verb_score
    )
    return {
        "sequence_score": round(sequence_score, 6),
        "token_score": round(token_score, 6),
        "verb_score": round(verb_score, 6),
        "overall_score": round(overall, 6),
    }
