#!/usr/bin/env python3
"""Reference implementation of the live thinking line (METRICS 6.9, Live thinking).

  python3 spec/tools/live_thinking.py     check the `thinking` cases of spec/fixtures/perf-score-cases.json

Imported by perf_score.py, which checks the same cases with the rest of that fixture.

Every output token generating in the 3-second window (METRICS 6.3) weighs `w`; the part of it that is reasoning is
`ρ`. `liveThinking = Σ ρ / 3 s`, `thinkingShare = Σ ρ / Σ w'`. The same sums restricted to one agent, or added over a
board group's members, give that agent's or group's values; restricted to one model, the per-model values that live
reporting sends (METRICS 11.10). It reuses the engine's confirmed decode intervals
(reference.py); nothing here reads a log.
"""
from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference as engine  # noqa: E402

NO_SEPARATE_REASONING = ("deepseek",)             # sources whose output does not split out reasoning (METRICS 4.3)


class Window:
    """The weighted sums of METRICS 6.9 Live thinking for one set of responses and agents at one instant."""

    def __init__(self):
        self.weight = self.reasoning = self.reasoning_weight = 0.0

    def add(self, source, weight, reasoning):
        self.weight += weight
        if source not in NO_SEPARATE_REASONING:
            self.reasoning += reasoning
            self.reasoning_weight += weight

    @property
    def thinking_share(self):
        return self.reasoning / self.reasoning_weight if self.reasoning_weight > 0 else 0.0

    def merge(self, other):
        self.weight += other.weight
        self.reasoning += other.reasoning
        self.reasoning_weight += other.reasoning_weight

    def result(self):
        return {"liveThinking": self.reasoning / (engine.WINDOW_MS / 1000), "thinkingShare": self.thinking_share,
                "weight": self.weight}

def seq_sum(values, start=0):
    """Left-to-right addition (METRICS 6.11): Python 3.12+ `sum` compensates float rounding, the ports do not."""
    total = start
    for value in values:
        total = total + value
    return total



def reasoning_share(responses):
    output = seq_sum(r["output"] for r in responses)
    return seq_sum(min(r.get("reasoning", 0), r["output"]) for r in responses) / output if output > 0 else 0.0


def contributions(responses, agents, now):
    """Every contribution of the window as (agent id, source, weight, reasoning, model): a finalized response's own model."""
    w0 = now - engine.WINDOW_MS
    measured = [r for r in responses if engine.interval(r) is not None and engine.is_final(r)]
    found = []

    for r in measured:
        start, end = engine.interval(r)
        share = engine.overlap(w0, now, start, end) / (end - start)
        if share <= 0:
            continue
        found.append((r["agentId"], r["source"], r["output"] * share, min(r.get("reasoning", 0), r["output"]) * share,
                      r.get("model")))

    return found


def window_sums(responses, agents, now):
    """The sums of the whole set and of every agent with a contribution: (total, {agent id: Window})."""
    total, per_agent = Window(), {}
    for agent_id, source, weight, reasoning, _ in contributions(responses, agents, now):
        total.add(source, weight, reasoning)
        per_agent.setdefault(agent_id, Window()).add(source, weight, reasoning)
    return total, per_agent


def model_sums(responses, agents, now):
    """METRICS 6.9 Model sums: {raw model, "" when unknown: Window} for every model with a contribution. Live
    reporting adds the sums of the raw models that resolve to one report id (11.3)."""
    per_model = {}
    for _, source, weight, reasoning, model in contributions(responses, agents, now):
        per_model.setdefault(model or "", Window()).add(source, weight, reasoning)
    return per_model


def group_window(per_agent, members):
    window = Window()
    for agent_id in members:
        if agent_id in per_agent:
            window.merge(per_agent[agent_id])
    return window


def board_groups(agents):
    """DESIGN 2c groups: every root (no parent, or a parent that is not listed) with all its descendants, the root
    first and then depth first in list order, keyed by the root's id."""
    ids = {a["id"] for a in agents}
    children, roots = {}, []
    for a in agents:
        parent = a.get("parentId")
        if parent in ids and parent != a["id"]:
            children.setdefault(parent, []).append(a["id"])
        else:
            roots.append(a["id"])
    groups = {}
    for root in roots:
        members, stack = [], [root]
        while stack:
            agent_id = stack.pop()
            members.append(agent_id)
            stack.extend(reversed(children.get(agent_id, [])))
        groups[root] = members
    return groups


def main():
    import json
    import perf_score
    with open(perf_score.FIXTURE, encoding="utf-8") as f:
        data = json.load(f)["thinking"]
    inputs = perf_score.inputs_of({"thinking": data})["thinking"]
    got = perf_score.compute_thinking(inputs)
    failures = perf_score.diff(got, data, "thinking") if not perf_score.close(got, data) else []
    if failures:
        print("\n".join(failures[:40]))
        return 1
    print("live thinking matches %d cases" % sum(len(c["queries"]) for cases in data.values() for c in cases))
    return 0


if __name__ == "__main__":
    sys.exit(main())
