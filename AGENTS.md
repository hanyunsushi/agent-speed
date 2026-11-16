# Agent Speed fork maintenance

- Read local `agent.md` when present, then [Windows fork operations](docs/windows-fork.md).
- Keep Windows packages, install commands and update checks on `hanyunsushi/agent-speed`.
- Preserve user settings, history, credentials and caches during executable updates.
- Run the Windows solution tests and relevant independent specification checks before release.
- Distributed packages must contain real Linux relays and both Windows native helpers. Never use fixture relays.
- Use `llm-wiki` after meaningful code, build, verification or release changes: synchronize the local project
  authority and affected `.llm-wiki/` pages. Keep private machine state out of Git.
- Keep upstream attribution and character/model-price data sources unless explicitly changing those contracts.
