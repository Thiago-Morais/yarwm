# Phase 4 — Rotation

**Milestone:** `next` and `skip` change the wallpaper by hand.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

### Step 19 — Selection state

**Branch** `feature/selection-state` · **Commit** `feat(selection): add selection state with recent ring buffer` · **Spec** §7 (Selection state)

`internal/selection/state.go`:

```go
type Shown struct {
	Hash      string `json:"hash"`
	CachePath string `json:"cache_path"`
}

type NextPick struct {
	Hash                string `json:"hash"`
	CachePath           string `json:"cache_path"`
	SnapshotFingerprint string `json:"snapshot_fingerprint"`
}

type State struct {
	Recent              []Shown   `json:"recent"`
	Next                *NextPick `json:"next"`
	BrowsePointer       int       `json:"browse_pointer"`
	ClampOnNextRotation bool      `json:"clamp_on_next_rotation"`
}

func LoadState(path string) (State, error) // missing file → empty state
func (state State) Save(path string) error

func (state *State) Current() (Shown, bool)            // Recent[0]
func (state *State) PushRecent(shown Shown, depth int) // prepend, cap at depth
func (state *State) Clamp()                            // Recent = Recent[BrowsePointer:], pointer 0, flag false
```

**Tests:** `PushRecent` prepends and caps · `Clamp` at pointer 2 drops the
first two entries and resets both fields · `Current` on empty state ·
JSON round-trip matches the spec's shape.

### Step 20 — Snapshot fingerprint

**Branch** `feature/fingerprint` · **Commit** `feat(selection): fingerprint the inputs of the next pick` · **Spec** §7 (`next.snapshot_fingerprint`)

`internal/selection/fingerprint.go`:

```go
// Fingerprint is a SHA-256 over everything the next pick depends on:
// the scoring and library settings from config, the active quality
// filter, and the size + modification time of each given file
// ("missing" for absent files).
func Fingerprint(settings config.Config, activeFilter filter.Range, files ...string) (string, error)
```

Callers pass `tags.json` and `library_index.json`. History is *not* passed:
it changes on every rotation, and the next pick is computed right after the
history is saved, so it's already accounted for.

**Tests:** same inputs → same fingerprint · changing `base_f`, the filter,
or touching a listed file each change it · a missing file is stable.

### Step 21 — Rotation: generating a new wallpaper

**Branch** `feature/rotation` · **Commit** `feat(selection): rotate to a new wallpaper` · **Spec** §6 steps 1–5, §7 (real rotation, `browse_pointer == 0` branch) · **Decisions** D8

`internal/selection/rotate.go` — the core of the program.

```go
type Dependencies struct {
	Config  config.Config
	Display backend.Displayer
	Random  *rand.Rand
	Now     func() time.Time
}

type RotateOptions struct {
	ExplicitFilter *filter.Range // from CLI flags; nil = use the fallback chain
	Skip           bool          // add skip_penalty_seconds to the outgoing wallpaper
}

// Rotate shows a new wallpaper and records it. Returns what was shown.
func Rotate(ctx context.Context, dependencies Dependencies, options RotateOptions) (Shown, error)
```

Steps, all under the state lock:

1. Load selection state, tags, history; resolve the active filter (step 18).
2. Scan the library and refresh the index; save the index if it changed (D8).
3. Fingerprint (step 20). If `state.Next` exists, its fingerprint matches,
   and its file still exists → use it. Otherwise build the pool excluding
   the current wallpaper and `Pick`.
4. **Show it.** If the backend fails, return the error and change nothing.
5. Close out the outgoing wallpaper (`CloseOut`, with
   `skip_penalty_seconds` as extra when `Skip`), `SetLastShown` for the new
   one, save history.
6. `PushRecent` the new one.
7. Precompute the following pick (excluding the new current), fingerprint
   it, store it in `state.Next`; save the state.

This step only handles `BrowsePointer == 0`. Browsing arrives in step 28;
until then, if the pointer isn't 0, return an error.

**Tests** (fake `Displayer` recording paths, fixed clock, seeded random,
temp library and XDG dirs):
- first rotation on empty state shows an image and fills `recent` and `next`
- the second rotation shows exactly the previous `next`
- tagging a file between rotations (fingerprint changes) → `next` is recomputed
- a precomputed `next` whose file was deleted → recomputed
- backend error → no state, history or tags file changed
- the outgoing wallpaper gets its screen time; with `Skip`, plus the penalty
- `recent` stays capped at `history_depth`
- the same wallpaper never shows twice in a row with 2+ images
- empty library → `ErrEmptyPool`

### Step 22 — `next` and `skip`

**Branch** `feature/next-skip` · **Commit** `feat(cli): add next and skip commands` · **Spec** §7

- `yarwm next [--quality ...]` and `yarwm skip [--quality ...]` call
  `Rotate` (with `Skip: true` for skip) and print the shown path.
- Build `Dependencies` from the loaded config; `backend.New` errors with
  `ErrBackendNotConfigured` → print that message (it names the config
  file).
- Add one helper in `internal/cli` that every command needing config
  uses: `config.EnsureFile`, print the first-run warning if the file was
  just created, then `config.Load` and `Validate`.
- Manual commands ignore `paused` (spec §7).
- `next [N]` with a count and cursor movement arrive in step 28; for now
  `next` takes no arguments.

**Tests:** command-level with a fake backend (inject through a package
variable or a `Dependencies` factory): `next` prints a path and updates
state · `skip` adds the penalty · no backend configured → exit 1 with the
message.

**Try it (milestone):** configure `[wallpaper_command]` for awww in
`~/.config/yarwm/config.toml`, then `./build/yarwm next` changes your
wallpaper.

### Step 23 — `tag` keyword targets

**Branch** `feature/tag-keywords` · **Commit** `feat(cli): tag current, last and next by keyword` · **Spec** §1 (Tag target keywords) · **Decisions** D15

- `yarwm tag [current|last|next|<file>] [--quality N] [--frequency N]`;
  no target means `current`.
- `current` → `Recent[0]`, `last` → `Recent[1]`, from the selection state.
  Clear error when empty ("nothing shown yet").
- `next` → the precomputed pick, refreshed first if its fingerprint is
  stale. Put that refresh in `internal/selection` as
  `EnsureNext(ctx, dependencies) (NextPick, error)` — under the state lock,
  it recomputes and **saves** (D15); step 30 reuses it.
- A literal file named `current` is reachable as `./current`.

**Tests:** each keyword resolves to the right hash · no target = current ·
empty state → error · stale `next` is recomputed and saved.
