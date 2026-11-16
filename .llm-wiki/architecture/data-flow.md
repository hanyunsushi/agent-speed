# Data flow

Agent transcript/database discovery → source parser → `ParsedResponse` → `SpeedEngine` →
snapshot → presentation → taskbar/orb/dashboard. Completion summaries include decode speed
and TTFT. History analysis aggregates daily usage; performance evaluation and reporting use
the same positive measurement intervals.

Independent Python implementations and JSON fixtures under `spec/` exercise the contracts.
User settings and retained SQLite history live outside the source tree. Executable replacement
preserves these paths.

See [architecture](overview.md) and [measurements](../concepts/measurements.md).
