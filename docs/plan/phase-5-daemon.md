# Phase 5 — Daemon

**Milestone:** automatic rotation on clock-aligned ticks, then release v0.1.0.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

### Step 24 — Tick schedule and `time_left`

**Branch** `feature/schedule` · **Commit** `feat(schedule): align ticks to midnight and add time_left` · **Spec** §5, §7 (`time_left`) · **Decisions** D11

`internal/schedule/schedule.go`:

```go
// NextTick is the first tick strictly after now. Ticks are every interval
// from local midnight; the day's ticks restart at the next midnight.
func NextTick(now time.Time, interval time.Duration) time.Time

// FormatDuration prints "1h 4m 12s", "4m 12s", "12s" — rounded up to
// whole seconds, "0s" at minimum.
func FormatDuration(duration time.Duration) string
```

Get midnight with `time.Date(year, month, day, 0, 0, 0, 0, now.Location())`
so daylight-saving days work.

`yarwm time_left [--seconds]`: human-readable by default; `--seconds`
prints the remaining seconds with 3 decimals.

**Tests:** 13:05 with 600 s → 13:10 · exactly 13:10 → 13:20 (strictly
after) · 5 s → next multiple of 5 · 7 h → 07:00, 14:00, 21:00, then
midnight · 0.5 s intervals · a DST-change day (use a real zone, e.g.
`time.LoadLocation("America/New_York")`) · `FormatDuration` cases.

### Step 25 — `pause` and `resume`

**Branch** `feature/pause` · **Commit** `feat(cli): add pause and resume` · **Spec** §7

- `yarwm pause` creates the `paused` file; `yarwm resume` removes it. Both
  are idempotent and print the resulting state.
- `selection.IsPaused() (bool, error)` for the daemon (step 26) and
  `status` (step 31).

**Tests:** pause → paused · pause twice → still paused, no error · resume →
not paused · resume when not paused → no error.

### Step 26 — `start` (the daemon)

**Branch** `feature/daemon` · **Commit** `feat(daemon): rotate on aligned ticks` · **Spec** §5, §7 (daemon startup) · **Decisions** D13, D14

`internal/daemon/daemon.go`:

```go
type Options struct {
	ExplicitFilter *filter.Range
	// WaitUntil sleeps until the given time or until ctx is cancelled.
	// Real runs use a time.Timer; tests return immediately.
	WaitUntil func(ctx context.Context, moment time.Time) error
}

func Run(ctx context.Context, dependencies selection.Dependencies, options Options) error
```

1. `TryAcquire(paths.DaemonLockFile())`; `ErrLocked` → "yarwm is already
   running" (D14). Hold it until exit.
2. If an explicit filter was given, save it as the session filter (spec §7).
3. If `Recent[0]` exists and its file exists, show it (no rotation, D13);
   otherwise `Rotate`.
4. Loop: wait until `schedule.NextTick(now, interval)`; if paused, log and
   continue; otherwise `Rotate`. Log errors and keep going — one failed
   rotation must not kill the daemon.
5. Stop cleanly on SIGINT/SIGTERM (`signal.NotifyContext`).

`yarwm start [--quality ...]` wires it up and logs one line per tick to
stderr (`2026-11-04 13:10:00 showing /path/x.jpg`).

**Tests** (fake `WaitUntil` that cancels after N ticks, fake backend):
three ticks → three rotations · paused → no rotations · startup re-shows
`Recent[0]` without changing history · empty state → startup rotation ·
second `Run` while one holds the lock → "already running" · a backend
error on one tick doesn't stop the loop.

**Try it:** `./build/yarwm start` in a terminal with `interval = 5` in your
config, then add `exec-once = /path/to/yarwm start` to your Hyprland config.

### Step 27 — Reload only on change

**Branch** `feature/reload-on-change` · **Commit** `feat(daemon): reload state files only when they change` · **Spec** §5 (last bullet), §10

The daemon re-reads every JSON file each tick. Cheap at 10-minute
intervals, wasteful at sub-second ones.

- Add a cache to `internal/jsonstore`:
  `type CachedFile[T any]` with `Load(path string) (T, error)` that keeps
  the decoded value with the file's size + mtime and decodes again only when
  they change. Writes through the store update the cache.
- Use it for the daemon's reads of tags, history, selection state and
  config (so config edits apply without a restart). One-shot CLI commands
  keep plain reads.

**Tests:** second `Load` without a change doesn't decode (count decodes) ·
after modifying the file it decodes again · a write through the cache is
seen by the next `Load`.

**Release v0.1.0** after this step (release flow in `CONTRIBUTING.md`).
