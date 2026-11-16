---
title: Agent Speed fork wiki schema
updated: 2026-11-16
last_synced_commit: 334ba152f3c6160070be4ffa233047cd87d1badb
commit_policy: committed
authority_entry: ../docs/windows-fork.md
---

# Scope and ownership

This wiki covers the Windows fork and the shared contracts it uses. Upstream specifications own
cross-platform formulas. `docs/windows-fork.md` owns public build/install/rollback instructions;
local `agent.md` points to private machine deployment facts. `AGENTS.md` owns agent behavior.

Stack: C#/.NET 10, WPF, xUnit, PowerShell, Python reference checks; Swift/macOS and C++/Qt/Linux
remain in the monorepo. Articles use relative links and source paths with symbols. No event log.

See [index](_index.md) and [sync state](_sync-state.md).
