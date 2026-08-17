---
card_id: flowtone-finish-crossfade-math
status: frozen
version: 1
supersedes: null
work_id: flowtone-finish
task_id: crossfade-math
purpose: Implement deterministic equal-power gains and safe duration clamping.
role: developer
route: P3 -> developer / gpt-5.6-terra / medium
card_path: docs/orda/flowtone-finish/crossfade-math.md
card_commit_sha: launch-envelope
base_sha: gate0-card-commit
dependency_shas:
  - 2aad8e55cdf3bf2a2275f48ca1b9ac5d67b4163e
branch: codex/flowtone-crossfade-math
branch_base_sha: gate0-card-commit
write_scope:
  - Sources/FlowtoneCore/EqualPowerCrossfade.swift
  - Tests/FlowtoneCoreTests/EqualPowerCrossfadeTests.swift
forbidden_paths:
  - Sources/FlowtoneApp/
  - Sources/FlowtoneCore/RadioPlaybackQueue.swift
  - Sources/FlowtoneCore/AudioPlaybackController.swift
contract_versions:
  input: crossfade-plan-v1
  output: crossfade-plan-v1
acceptance_commands:
  - swift test --filter EqualPowerCrossfadeTests
  - swift build --product Flowtone
---

# Equal-power crossfade plan

- Clamp progress to `0...1`.
- Gains: `cos(πp/2)` and `sin(πp/2)`; squared-gain sum stays approximately one.
- Effective duration: `max(0, min(requested, currentDuration / 4, nextDuration / 4))`.
- Invalid or non-positive durations return zero.
- Commit the feature branch and return SHA, paths, test evidence and risks. Do not merge or force-push.
