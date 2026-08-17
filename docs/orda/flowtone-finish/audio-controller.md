---
card_id: flowtone-finish-audio-controller
status: frozen
version: 1
supersedes: null
work_id: flowtone-finish
task_id: audio-controller
purpose: Implement a two-node AVAudioEngine controller behind a testable backend seam.
role: developer
route: P4 -> developer / gpt-5.6-terra / high
card_path: docs/orda/flowtone-finish/audio-controller.md
card_commit_sha: launch-envelope
base_sha: gate0-card-commit
dependency_shas:
  - a2ef3c4cd80e5778be7b8204bb01b531fc54035c
branch: codex/flowtone-audio-controller
branch_base_sha: gate0-card-commit
write_scope:
  - Sources/FlowtoneCore/AudioPlaybackController.swift
  - Tests/FlowtoneCoreTests/AudioPlaybackControllerTests.swift
forbidden_paths:
  - Sources/FlowtoneApp/
  - Sources/FlowtoneCore/EqualPowerCrossfade.swift
  - Sources/FlowtoneCore/RadioPlaybackQueue.swift
contract_versions:
  input: audio-controller-v1
  output: audio-controller-v1
acceptance_commands:
  - swift test --filter AudioPlaybackControllerTests
  - swift build --product Flowtone
---

# AVAudioEngine playback controller

- Input item is UUID plus local file URL; own no library-selection policy.
- Accept current, optional next and scalar crossfade duration.
- Inject gain provider `(normalizedProgress) -> (outgoing, incoming)` so Wave 1 tasks have no compile dependency.
- Support play, pause, skip, volume, next replacement, transition callback and next-needed callback.
- Schedule transition from player/render timing rather than doing a filesystem lookup at the boundary.
- Expose current and queued IDs; mutate no `TrackLibrary` state.
- Tests use injected backend/clock seams and no audio hardware.
- Commit the feature branch and return SHA, paths, test evidence and risks. Do not merge or force-push.
