---
card_id: flowtone-finish-package-app
status: frozen
version: 1
supersedes: null
work_id: flowtone-finish
task_id: package-app
purpose: Add reproducible unsigned macOS app packaging and CI verification without credentials.
role: devops
route: P3 -> devops / gpt-5.6-terra / medium
card_path: docs/orda/flowtone-finish/package-app.md
card_commit_sha: wave1-final-merge
base_sha: wave1-final-merge
dependency_shas:
  - wave1-final-merge
branch: codex/flowtone-package-app
branch_base_sha: wave1-final-merge
write_scope:
  - scripts/package-app.sh
  - .github/workflows/ci.yml
forbidden_paths:
  - Sources/
  - Tests/
  - Package.swift
contract_versions:
  input: package-app-v1
  output: package-app-v1
acceptance_commands:
  - bash -n scripts/package-app.sh
  - scripts/package-app.sh /tmp/Flowtone-package-test
  - plutil -lint /tmp/Flowtone-package-test/Flowtone.app/Contents/Info.plist
---

# Unsigned app packaging and CI

- Build the release `Flowtone` executable and assemble a standard `Flowtone.app` bundle.
- Accept an explicit output directory; default safely to `dist` without deleting unrelated content.
- Generate a valid `Info.plist`, copy the executable, and validate the bundle locally.
- CI must lint Swift, run tests, build release, and exercise packaging on macOS.
- Do not sign, notarize, publish releases, add secrets, or change source code.
- Commit the feature branch and return SHA, paths, test evidence, and risks. Do not merge or push.
