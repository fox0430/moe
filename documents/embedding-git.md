# Git updates in embedding frontends

Moe owns Git subprocesses and diffs against the current buffer contents, including
unsaved edits. The host owns filesystem watching and workspace file discovery.

The default refresh mode is `grmPeriodic`: visible buffers refresh their diffs on
edits, explicit requests and the configured Git interval; branches refresh every
five seconds. Branch lookups run asynchronously and are shared by buffers in the
same worktree. Linked worktrees keep separate branch state.

A host with filesystem and Git metadata watchers can disable elapsed-time
refreshes:

```nim
import moepkg/frontend

let editor = newEditor(newEditorConfig())
editor.setFrontendGitStatusEnabled(true)
editor.setFrontendGitRefreshMode(grmEventDriven)

# On the editor thread, after coalescing watcher events:
editor.notifyGitRepositoryChanged("/absolute/path/to/worktree")

# In the host's normal editor update loop:
editor.tick()
let revision = editor.frontendGitStatusRevision()
let status = editor.frontendStatus()
```

`notifyGitRepositoryChanged` takes a worktree root, not a `.git` directory. An
empty argument invalidates every cached repository. The call marks results stale
without launching processes. Continue calling `tick` to schedule work for buffers
with Git consumers and reap all pending children, including hidden-buffer work.
Marshal notifications onto the editor thread; do not call these APIs directly
from watcher threads. The host should coalesce event bursts before notifying Moe.

Event-driven mode still performs initial queries and reacts to buffer edits,
saves and reloads. The host must notify external commits, checkouts, index/ignore
changes and repository creation/removal. Disabling frontend status maintenance
does not disable the terminal gutter or status line's independent consumption of
the same cache. Selecting event-driven mode disables TTL refreshes for all those
consumers in this editor.

The completion revision advances when results are published. Hosts can compare
it after `tick` to refresh their UI without installing callbacks. Buffer activation
can change the displayed status without changing the revision, so hosts should
also refresh on their normal buffer-selection events. Read `frontendStatus` for
the active buffer; it never starts Git work.

Diff results superseded by a path change, edit or repository notification are
discarded. The last published counts remain available until a current result
arrives. Branch queries invalidated while running are discarded as well.

Worktree discovery walks ancestor directories for `.git` files or directories,
resolving directory symlinks. Normal repositories, linked worktrees and submodules
are supported; custom repositories selected only through `GIT_DIR`/`GIT_WORK_TREE`
environment overrides are not part of this discovery contract.

Closing a buffer releases its pending diff and its branch query if no other
buffer uses that worktree. Editor shutdown releases all outstanding Git work.
Cancellation and timeout allow a short termination grace period, then kill and
reap the child before closing handles and removing scratch files. Call
`releaseExternalResources()` when disposing of an embedded editor.
