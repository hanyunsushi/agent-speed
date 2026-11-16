# Testing

Run `dotnet test windows/AgentSpeed.slnx -c Release` for core, presentation, traffic helper,
status-line helper and native Windows desktop tests. Native tests require Windows/WPF.
Directory-alias tests use junctions on Windows and symlinks elsewhere. Remote Unix shell cases
and published-executable status-line checks have platform/artifact prerequisites.

Independent checks: `python spec/tools/perf_score.py`,
`python spec/tools/perf_score_cases.py`, `python spec/tools/report_reference.py`.
Upstream CI also runs specification fixtures, Linux relays and macOS verification.
Run performance/allocation tests on a quiet machine; runtime tiering can cause a transient allocation.
Do not weaken those assertions to hide an environmental failure.

See [setup](setup.md) and [measurements](../concepts/measurements.md).
