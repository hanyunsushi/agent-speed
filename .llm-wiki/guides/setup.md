# Setup

Clone `hanyunsushi/agent-speed` and use the .NET 10 SDK. See
[Windows fork operations](../../docs/windows-fork.md) for prerequisites and publish commands.
The `Windows fork` GitHub Actions workflow builds Linux relays on their native runners, then
publishes Windows x64 and ARM64 in separate jobs, including native traffic/status-line helpers.
Its artifacts contain archives and checksums; artifact creation alone does not publish a release.
`Publish Windows artifacts` promotes a successful build to a draft release targeting the exact
build commit, checks SHA-256 on the runner and publishes the two Windows archives.

See [testing](testing.md) and [directory structure](../architecture/directory-structure.md).
