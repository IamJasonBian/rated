"""
"For you" movie recommendations — small user-user collaborative filter.

Taste similarity between the viewer and another rater is their mean score
agreement on movies both rated (1 = identical scores, 0 = 9 points apart),
shrunk toward 0 when they share few movies. People the viewer follows get a
fixed boost. A candidate movie's predicted score is the similarity-weighted
mean of the raters' scores, shrunk toward the global mean score. Fine at pilot scale (one pass over rankings).
"""

from __future__ import annotations

from collections import defaultdict

SHRINK = 2          # overlap / (overlap + SHRINK): 1 shared movie → 0.33 weight
FOLLOW_BOOST = 0.25
MIN_SIM = 0.05
PRIOR = 1.0         # pseudo-weight pulling thin-evidence picks toward the global mean


def group_by_user(rows) -> dict[str, dict[str, int]]:
    """(user_id, movie_id, score) rows -> {user_id: {movie_id: score}}."""
    by_user: dict[str, dict[str, int]] = defaultdict(dict)
    for user_id, movie_id, score in rows:
        by_user[user_id][movie_id] = score
    return dict(by_user)


def recommend(
    viewer_id: str,
    by_user: dict[str, dict[str, int]],
    following: set[str],
    n: int = 10,
) -> list[dict]:
    """Rank movies the viewer hasn't rated by predicted score.

    Args:
        viewer_id: User to recommend for.
        by_user: user_id -> {movie_id: score} for every rater.
        following: user_ids the viewer follows (approved).
        n: Max results.

    Returns:
        [{"movie_id", "predicted", "support", "because"}] best first;
        `because` lists up to 3 most-similar raters who scored it >= 8.
        Empty when the viewer has rated nothing.
    """
    mine = by_user.get(viewer_id, {})
    if not mine:
        return []

    sims: dict[str, float] = {}
    for user_id, theirs in by_user.items():
        if user_id == viewer_id:
            continue
        shared = mine.keys() & theirs.keys()
        sim = 0.0
        if shared:
            agree = sum(1 - abs(mine[m] - theirs[m]) / 9 for m in shared) / len(shared)
            sim = agree * len(shared) / (len(shared) + SHRINK)
        if user_id in following:
            sim += FOLLOW_BOOST
        if sim >= MIN_SIM:
            sims[user_id] = sim

    n_scores = sum(len(m) for m in by_user.values())
    prior = sum(sum(m.values()) for m in by_user.values()) / n_scores
    weighted: dict[str, float] = defaultdict(float)
    weight: dict[str, float] = defaultdict(float)
    fans: dict[str, list[tuple[float, str]]] = defaultdict(list)
    for user_id, sim in sims.items():
        for movie_id, score in by_user[user_id].items():
            if movie_id in mine:
                continue
            weighted[movie_id] += sim * score
            weight[movie_id] += sim
            if score >= 8:
                fans[movie_id].append((sim, user_id))

    out = [
        {
            "movie_id":  movie_id,
            "predicted": round(
                (weighted[movie_id] + PRIOR * prior) / (weight[movie_id] + PRIOR), 2),
            "support":   round(weight[movie_id], 2),
            "because":   [u for _, u in sorted(fans[movie_id], reverse=True)[:3]],
        }
        for movie_id in weight
    ]
    out.sort(key=lambda r: (r["predicted"], r["support"]), reverse=True)
    return out[:n]
