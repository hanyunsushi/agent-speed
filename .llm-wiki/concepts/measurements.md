# Measurements

`SpeedMath.TryGetSpeedInterval` validates request timing (no more than 15 minutes), then uses
first content when it lies between request start and completion. Unknown or invalid first content
falls back to request start. A positive interval is required; no 500 ms minimum is applied.

TTFT is first content minus request start and remains separate from decode throughput.
History analysis version 12 invalidates cached analysis when upgrading from request-duration builds;
available logs are reanalysed. The bundled Linux relay uses the same positive decode durations.
`spec/tools/perf_score_cases.py` derives hand-checked performance expectations;
`spec/tools/report_perf_score.py` independently checks reporting statistics. Devin/Qoder fixture
generators compute history totals using the same specification, without calling the C# implementation.

See [metrics](../../spec/METRICS.md), [modules](../modules/windows.md) and [testing](../guides/testing.md).
