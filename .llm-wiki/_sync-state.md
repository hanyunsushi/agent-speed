# Documentation impact

Base: `85cc4644` (the existing TPS/TTFT branch). Scope: Windows packaging/update URLs,
portable tests and shared measurement fixtures. Operations are owned by `docs/windows-fork.md`;
code contracts are summarized in modules, measurements, updates and testing pages.

Cross-platform regression also covers the Linux relay's history duration, analysis-cache invalidation
(Windows/macOS 12, Linux 7), and the Linux/macOS short-response test expectations. All changed source
paths are covered by measurements, Windows modules and the public release notes.

The local authority records machine installation and rollback identity. CodeGraph is unavailable
on the Windows host; source inspection uses `rg` and direct reads. Native WPF controls keep the
existing design and accessibility contracts; this change adds no UI controls or web locators.

See [index](_index.md) and [schema](_schema.md).
