---
card_id: flowtone-finish-model-runtime
status: frozen
version: 1
supersedes: null
work_id: flowtone-finish
task_id: model-runtime
purpose: Discover an installed local Stable Audio 3 runtime and expose deterministic tier availability without downloads or license acceptance.
role: developer
route: P3 -> developer / gpt-5.6-terra / medium
card_path: docs/orda/flowtone-finish/model-runtime.md
card_commit_sha: wave1-final-merge
base_sha: wave1-final-merge
dependency_shas:
  - wave1-final-merge
branch: codex/flowtone-model-runtime
branch_base_sha: wave1-final-merge
write_scope:
  - Sources/FlowtoneCore/ModelRuntimeCatalog.swift
  - Tests/FlowtoneCoreTests/ModelRuntimeCatalogTests.swift
forbidden_paths:
  - Sources/FlowtoneApp/
  - Sources/FlowtoneCore/GenerationScheduler.swift
  - scripts/
  - .github/
contract_versions:
  input: model-runtime-v1
  output: model-runtime-v1
acceptance_commands:
  - swift test --filter ModelRuntimeCatalogTests
  - swift build --product Flowtone
---

# Installed local model runtime

- Inspect only deterministic application-support or injected test roots.
- Light tier may resolve an executable Stable Audio 3 adapter and build a `StableAudioCLIEngine`.
- Quality tier must report an explicit unavailable or unsupported state until a verified ACE-Step adapter exists.
- Never download weights, accept gated terms, run installers, or modify user model files.
- Test missing, executable, and non-executable paths in temporary directories.
- Commit the feature branch and return SHA, paths, test evidence, and risks. Do not merge or push.
