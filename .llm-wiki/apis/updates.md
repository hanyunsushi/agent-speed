# Update boundary

Windows `UpdateSource.GitHubFeedUrl` points to
`https://api.github.com/repos/hanyunsushi/agent-speed/releases/latest`.
The public fallback uses the same repository's release page/Atom feed. Release assets are
architecture-specific ZIPs checked against `SHA256SUMS.txt`. HTTPS redirects remain restricted
to GitHub's allow-listed asset hosts. Cookies and account credentials are never attached.

The local-only `AGENT_SPEED_UPDATE_FEED` override is for test feeds; tests cover fallback errors,
unsafe redirects, malformed feeds and cancellation. Installer `$Repo` uses this fork too.

See [update contract](../../spec/UPDATES.md), [modules](../modules/windows.md)
and [operations](../../docs/windows-fork.md).
