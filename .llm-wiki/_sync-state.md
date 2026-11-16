# Documentation impact

Base: `85cc4644` (the existing TPS/TTFT branch). Scope: Windows packaging/update URLs,
portable tests and shared measurement fixtures. Operations are owned by `docs/windows-fork.md`;
code contracts are summarized in modules, measurements, updates and testing pages.

The local authority records machine installation and rollback identity. CodeGraph is unavailable
on the Windows host; source inspection uses `rg` and direct reads. Native WPF controls keep the
existing design and accessibility contracts; this change adds no UI controls or web locators.

See [index](_index.md) and [schema](_schema.md).
