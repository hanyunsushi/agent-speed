# Directory structure

- `windows/src/AgentSpeed.Core`: parsing, engine, history, performance, reporting and networking.
- `windows/src/AgentSpeed.Presentation`: shared presentation models, formatting, characters and updates.
- `windows/src/AgentSpeed`: WPF application, taskbar, orb, dashboard, settings and native integrations.
- `windows/src/AgentSpeed.*Helper`: traffic-service and status-line executables.
- `windows/tests`: five test projects; `windows/tools`: probe and profile harnesses.
- `spec`: authoritative contracts, fixtures, public data and independent reference programs.
- `linux/relay`: native relay build; `linux/core`: Linux engine; `macos`: Swift application.
- `.github/workflows`: upstream CI/release plus the fork's Windows artifact workflow.
- `docs/windows-fork.md`: public fork operations; `.llm-wiki`: derived code knowledge.

See [architecture](overview.md) and [setup](../guides/setup.md).
