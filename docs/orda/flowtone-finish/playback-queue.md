---
card_id: flowtone-finish-playback-queue
status: frozen
version: 1
supersedes: null
work_id: flowtone-finish
task_id: playback-queue
purpose: Implement library-independent current plus two-ready queue state.
role: developer
route: P3 -> developer / gpt-5.6-terra / medium
card_path: docs/orda/flowtone-finish/playback-queue.md
card_commit_sha: launch-envelope
base_sha: gate0-card-commit
dependency_shas:
  - 2aad8e55cdf3bf2a2275f48ca1b9ac5d67b4163e
branch: codex/flowtone-playback-queue
branch_base_sha: gate0-card-commit
write_scope:
  - Sources/FlowtoneCore/RadioPlaybackQueue.swift
  - Tests/FlowtoneCoreTests/RadioPlaybackQueueTests.swift
forbidden_paths:
  - Sources/FlowtoneApp/
  - Sources/FlowtoneCore/EqualPowerCrossfade.swift
  - Sources/FlowtoneCore/AudioPlaybackController.swift
contract_versions:
  input: playback-queue-v1
  output: playback-queue-v1
acceptance_commands:
  - swift test --filter RadioPlaybackQueueTests
  - swift build --product Flowtone
---

# Current plus two-ready queue

- UUID-only state; no filesystem, library or AVFoundation access.
- Preserve insertion order, reject duplicates and cap ready entries at two.
- `advance` atomically promotes first ready entry.
- `protectedTrackIDs` is exactly current plus ready IDs.
- Removal leaves a valid state; expose whether prefill is needed.
- Commit the feature branch and return SHA, paths, test evidence and risks. Do not merge or force-push.
