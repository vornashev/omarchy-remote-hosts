# Project instructions

This repository is the source of truth for the `tema.remote-hosts` Omarchy
plugin, published as `omarchy-remote-hosts`. Follow these instructions as
repository constraints, then carry the user's requested work to completion.

## Operating mode

- Treat a request for action as authorization for reversible work in this
  repository. Do the work; do not stop after acknowledging it or presenting a
  plan.
- Infer routine details from the repository and existing conventions. Ask a
  focused question only when the answer would materially change the result and
  cannot be recovered from the code, tests, documentation, or prior context.
- Complete all locally authorized work before requesting approval for an
  external or irreversible action. Present a concrete, reviewable result when
  approval is required.
- Incorporate mid-task corrections without discarding valid completed work.
- Read only the files needed for the task and reuse existing patterns. Do not
  introduce a second convention beside an established one.
- Work directly by default. Use subagents only when the user requests
  delegation or parallel work and the task has genuinely independent slices.
- Keep progress and final responses concise: result first, then changed files,
  verification, and any concrete blocker. Avoid canned summaries and repeated
  status narration.

## Repository map

- `BarWidget.qml` is the Omarchy bar entry point and loads `Widget.qml`.
- `Widget.qml` owns the panel UI and invokes `helper.py` with one JSON request
  on stdin per process.
- `state/DraftState.qml` is the in-memory form draft shared across monitor
  instances. It is never persistent storage.
- `helper.py` is the Python standard-library backend and security boundary. Its
  JSON responses are consumed by QML; keep both sides synchronized.
- `askpass.py` is a deliberately minimal OpenSSH password pipe. It must not
  print diagnostics, tracebacks, or secrets.
- `tests/` uses temporary data and mocked external processes/network access.
- User-facing text defaults to English; Russian is the supported alternate language.

## Security and side-effect boundaries

- Never edit `/usr/share/omarchy/`.
- The live installed copy is
  `~/.config/omarchy/plugins/tema.remote-hosts`. Develop and test in this
  repository first. Deploy only when explicitly requested, using
  `scripts/deploy-local`.
- Never copy profiles, passwords, private keys, `known_hosts`, screenshots with
  real endpoints, or runtime data into this repository.
- Do not connect to real hosts, read real Secret Service entries, install
  packages or extensions, publish, push, enable/disable the plugin, restart the
  shell, or change `~/.ssh/config` without explicit user approval.
- Keep passwords out of argv, environment variables, logs, JSON responses,
  clipboard, files, exception text, and tracebacks. Password flow remains stdin
  or pipe based.
- Preserve strict SSH host-key verification. Never use
  `StrictHostKeyChecking=no`, `accept-new`, or an automatic replacement/removal
  of an existing key.
- Keep subprocess calls as fixed argv arrays without a local shell. Preserve
  `ssh -F /dev/null`, disabled local commands/forwardings where currently
  required, conservative path validation, and the fixed AI executable allowlist.
- Preserve ownership, permission, symlink, file-size, locking, atomic-write,
  import-preview token, endpoint-binding, and mounted-resource checks. Fail
  closed rather than adding a plaintext or permissive fallback.
- Tests and local verification must use synthetic endpoints, temporary
  directories, and fake external programs. No verification step may touch a
  real credential, host, mount, or user profile.

## Change discipline

- Fix the source of a defect. Keep changes scoped and remove code made obsolete
  by the change.
- Preserve compatibility with existing saved profile schema unless the task
  includes a complete migration. Reject unknown or secret-bearing fields.
- When changing a helper operation or data field, update validation, dispatch,
  QML request/response handling, tests, and README behavior/security
  documentation where applicable.
- Keep `helper.py` compatible with the system `python3` and the standard library.
  Do not add runtime dependencies without explicit approval.
- Add or change tests only for observable behavior, boundaries, invariants, or
  regressions. Do not test source text, field forwarding, or other
  implementation details.
- Do not edit generated/runtime files or deploy as part of ordinary validation.

## Verification

Run the narrowest meaningful check while developing. After a significant code
change, run the full repository checks once:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest discover -s tests
omarchy plugin validate "$PWD"
scripts/qml-lint
```

For documentation-only or other low-impact changes, verify the changed artifact
directly; do not run broad tests unless the change affects executable commands
or unresolved risk justifies them. Do not repeat passing checks without a new
change or failure.
