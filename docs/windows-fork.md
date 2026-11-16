# Windows fork

This fork keeps the native WPF Windows app and the decode-speed / TTFT changes from
`codex/decode-tps-ttft`. Windows installations and update checks use
`hanyunsushi/agent-speed`; character packs and model prices still use the upstream data sources.

## Install and update

Download `AgentSpeed-Windows-x64.zip` or `AgentSpeed-Windows-arm64.zip` from this fork's
[releases](https://github.com/hanyunsushi/agent-speed/releases), and verify the archive against
`SHA256SUMS.txt`. The installer selects the native architecture and preserves settings/history:

```powershell
irm https://raw.githubusercontent.com/hanyunsushi/agent-speed/main/install.ps1 | iex
```

Application: `%LOCALAPPDATA%\Programs\AgentSpeed\AgentSpeed.exe`.
Settings: `%APPDATA%\AgentSpeed\settings.json`.
History, caches and logs: `%LOCALAPPDATA%\AgentSpeed`.

## Build and verify

Use the .NET 10 SDK. A full publish also needs Visual Studio C++ build tools for NativeAOT
and the architecture being built. Build both Linux relays from this checkout first using
`linux/relay/build-static.sh x86_64` and `linux/relay/build-static.sh aarch64` on a Docker host.
The publish script rejects missing relays and embeds both of them with their SHA-256 hashes.

```powershell
dotnet test windows/AgentSpeed.slnx -c Release
./windows/scripts/publish.ps1 -Architectures x64
# Omit -Architectures to produce both Windows architectures.
```

`AGENT_SPEED_NO_HELPER=1` explicitly omits the traffic and status-line helpers; this is for
development builds with the documented loss of those features. Distributed fork packages
use the `Windows fork` workflow, which builds both relays and publishes x64/ARM64 packages
with both native helpers. Workflow artifacts include the package SHA-256.

Tests use junctions for directory-alias coverage on Windows, so they work without administrator
privileges or Developer Mode. Unix-only remote-shell tests remain skipped on Windows.

## Measurements

For a valid first-content timestamp, speed uses output tokens divided by the interval from
first content to completion. Unknown/invalid first content falls back to request start;
nonpositive durations are not measured. TTFT stays separate. Fixtures cover short responses,
missing first content, performance scores, report statistics and history totals.

## Local replacement and rollback

Close Agent Speed before replacing its executable. Keep the old executable and a settings
copy in a separate rollback folder; preserve the data directory. Restart the installed path
and verify the process, version and startup log. To roll back the executable, close the app,
restore the previous executable, then restart. Do not restore an old history database as part
of an executable rollback. Up to three usable previous executables may be retained.
