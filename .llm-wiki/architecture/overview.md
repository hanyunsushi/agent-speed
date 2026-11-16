# Architecture

The Windows app uses a shared C# core, a presentation assembly and a native WPF host.
`windows/src/AgentSpeed/App/Program.cs#Main` initializes single-instance handling, logging,
the WPF application and `AppController`. Core services discover supported agent logs and
databases, parse usage, compute speed and retain daily history. Presentation owns formatting,
view models, character behavior and update contracts. WPF owns windows and native integration.

The traffic helper is a restricted optional Windows service; the status-line helper bridges
Claude Code quotas. Linux relays provide opt-in remote host monitoring. Publishing embeds their
executables so one application replacement updates its bundled components.

See [data flow](data-flow.md), [directories](directory-structure.md) and [modules](../modules/windows.md).
