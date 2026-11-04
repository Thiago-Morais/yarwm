# Phase 6 — Browsing and extras

Browsing back through recent wallpapers, `status`, `rebucket`, user documentation, then release v0.2.0.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

### Step 28 — Browsing: `previous`, `next N`, `undo`, `redo`

**Branch** `feature/browsing` · **Commit** `feat(selection): browse recent wallpapers` · **Spec** §7 (two families, real rotation branches)

In `internal/selection`:

```go
// MoveBackward moves the pointer back by count (capped at the oldest
// entry), sets ClampOnNextRotation, and returns the entry to display.
func MoveBackward(state *State, count int, clampOnNextRotation bool) (Shown, error)

// MoveForward moves toward Recent[0]. needsRotation is true when it would
// move past 0 — the caller then runs a real rotation instead.
func MoveForward(state *State, count int, clampOnNextRotation bool) (shown Shown, needsRotation bool, err error)
```

Commands (each `[N]`, default 1): `previous` and `next` set
`ClampOnNextRotation` false; `undo` and `redo` set it true. Cursor moves
display `Recent[pointer]` and change nothing else — no history, no
generation. If the file is gone, report it and leave the pointer as it was.

Extend `Rotate` with the two remaining branches from spec §7:

- pointer ≠ 0 and **no clamp**: move the pointer one step toward 0, display
  that entry, and stop — no history close-out, no generation.
- pointer ≠ 0 and **clamp** (or `Skip`): `state.Clamp()`, then continue
  with normal generation.

Remove step 21's "pointer must be 0" error.

**Tests**, as scenarios from the spec:
- `previous` twice then three rotations → walks back to 0 one step per rotation, then generates
- `undo` twice then one rotation → clamps (`Recent[0]` becomes the peeked entry, newer ones dropped) and generates
- `skip` after `previous` → clamps despite the flag
- `next 3` at pointer 1 → rotation path (walks to 0)
- backward is capped at the oldest entry
- cursor moves never touch `history.json`

### Step 29 — `clamp`

**Branch** `feature/clamp` · **Commit** `feat(cli): add clamp command` · **Spec** §7 (`clamp`)

`yarwm clamp`: if the pointer isn't 0, run `state.Clamp()` and save,
without generating or displaying anything (the clamped entry is already on
screen). At pointer 0, say there's nothing to clamp.

**Tests:** clamp after `previous 2` → `Recent[0]` is the displayed entry,
pointer 0 · clamp at pointer 0 → no change.

### Step 30 — `query_next_image`

**Branch** `feature/query-next` · **Commit** `feat(cli): add query_next_image` · **Spec** §7 · **Decisions** D15

`yarwm query_next_image` prints `EnsureNext(...).CachePath` (step 23) —
recomputed and saved if stale (D15). Nothing is displayed.

**Tests:** prints the stored `next` · stale → recomputed, saved, printed ·
the following rotation shows the printed path.

### Step 31 — `status`

**Branch** `feature/status` · **Commit** `feat(cli): add status command` · **Spec** §7 (`status`)

```
current   /path/a.jpg  (quality 8, frequency 5)
last      /path/b.jpg
next      /path/c.jpg
browsing  2 back — next rotation walks back      ← only when pointer ≠ 0
filter    >= 7 (session)                         ← or "(config default)"
paused    no
next tick 4m 12s (252.000s)
```

Read-only: selection state, tags, session filter, paused file,
`schedule.NextTick`. Show `-` for empty fields.

**Tests:** empty state · full state · browsing line appears only when the
pointer isn't 0 and says "clamps" vs "walks back" from the flag · filter
source label.

### Step 32 — `rebucket`

**Branch** `feature/rebucket` · **Commit** `feat(history): add rebucket maintenance command` · **Spec** §6 (config changes) · **Decisions** D20

In `internal/history`:

```go
// Rebucket resamples one entry's buckets into the current layout,
// treating each old bucket as a uniform daily rate (spec §6).
// splits reports whether any old bucket had to be spread across
// several new ones.
func Rebucket(buckets map[string]float64, daysPerBucket int, now time.Time) (resampled map[string]float64, splits bool)
```

An old bucket's width isn't stored, so infer it: the number of days to the
next bucket's start, and for the newest bucket the days from its start to
`now` (at least 1) — time can't have been recorded in the future.

`yarwm rebucket`: report how many wallpapers would change and whether any
split happens; change nothing. `yarwm rebucket --force`: apply under the
state lock; if anything splits, ask `[y/N]` unless `--yes`.

**Tests:** merging 1-day into 7-day buckets is exact · splitting 7-day
into 1-day spreads evenly · total screen time is conserved in both
directions · `splits` is false for pure merges · without `--force` nothing
is written.

### Step 33 — User documentation and v0.2.0

**Branch** `feature/user-docs` · **Commit** `docs: add usage guide`

- README "Usage": install (`go install github.com/Thiago-Morais/yarwm@latest`
  or `make build`), first run, configuring the backend, tagging, migrating,
  running the daemon from Hyprland's `exec-once`, browsing commands.
- Verify the `awww` and `hyprpaper` examples in the config template against
  their current CLIs (spec §11 open item) and fix them if needed.
- Fold the confirmed [decisions](README.md#decisions) into `spec.md`.

**Release v0.2.0** after this step.
