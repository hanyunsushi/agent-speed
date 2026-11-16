# Windows modules

`SpeedEngine.Summarize` in `windows/src/AgentSpeed.Core/Engine/SpeedEngine.cs` creates response
summaries; `SpeedMath.TryGetSpeedInterval` owns valid measurement intervals. `PerfEvaluator`
and `ReportPerfLedger` reuse that contract. `AppController` adds TTFT to the taskbar/accessibility text.

`UpdateSource` in `windows/src/AgentSpeed.Presentation/Updates/UpdateSource.cs` owns release
URLs and redirect policy. `UpdateClient` fetches release metadata, falls back to public release
pages on network/rate-limit errors and validates package headers. `AppPaths` owns product paths
and source/release links. Character packs and public price data retain their upstream sources.

`windows/scripts/publish.ps1` builds selected Windows architectures, embeds native helpers and
both remote relays, and creates single-executable ZIPs.

See [architecture](../architecture/overview.md), [measurements](../concepts/measurements.md)
and [updates](../apis/updates.md).
