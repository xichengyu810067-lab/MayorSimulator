# Repository file disposition ledger

This directory is the auditable inventory for the current game and SDK source
trees. It does not authorize bulk deletion. Every path is assigned one of these
decisions:

- `RETAIN`: a project, SDK, test, tool, release, history, or runtime contract
  establishes a reason to keep the path.
- `RETAIN_BLOCKED`: the path is conservatively kept because visual quality,
  distribution rights, dynamic loading, source-art value, or human historical
  value still needs evidence.
- `REFACTOR_APPROVED`: unique value is established and a bounded rewrite has
  been approved. No path receives this decision automatically.
- `RETIRE_APPROVED`: reachability, uniqueness, recovery value, and rights have
  all been closed and a bounded removal has been approved. No path receives
  this decision automatically.

`file_disposition.json` pins the reviewed game commit/tree and the exact SDK
gitlink. The three governance files are an explicit overlay so the inventory
does not depend recursively on its own JSON blob hash.

The damaged legacy checkout at `C:\Users\USER\遊戲` and its archive/recovery
copies are outside this authoritative tree. They remain `RETAIN_BLOCKED` as a
separate recovery scope: their dirty work, large archives, and corrupted Git
packs must not be staged, rewritten, or deleted through this ledger.

Generate or validate the ledger from the game worktree:

```powershell
& ./tools/validate_file_disposition.ps1 -Write
& ./tools/validate_file_disposition.ps1
```

The validator fails on missing paths, unexpected paths, duplicate entries,
blank decisions/evidence, an SDK pin mismatch, or an unapproved decision. A
later refactor or retirement batch must update the ledger first, name an exact
dependency closure, use one revertable commit, and run the project gate that
proves the affected behavior. Public release remains outside this ledger and
blocked by the release-rights records.
