# Build "YARWM" (Yet Another Random Wallpaper Manager) for Hyprland

**Pronounced "YARM"** (rhymes with "arm," one syllable) — not spelled out
letter by letter.

## Overview
Build a lightweight CLI tool/daemon that automatically rotates the desktop
wallpaper on a Linux system (primarily used under Hyprland/Wayland), calling
out to whatever external wallpaper-setting program the user configures
(`awww` by default, chosen for animated transitions — but the tool must not
be hardcoded to it; see "Wallpaper backend" below). Wallpaper changes happen
on a clock-aligned schedule, and each new wallpaper is picked via a
weighted-random algorithm over a pool pre-filtered by a manually-assigned
quality tag, weighted by a separate manually-assigned frequency tag plus
anti-repetition/anti-staleness logic.

**Design priorities: small, clean, dependency-light, low resource usage
("should run fine on a potato"), portable across distros/init systems (do
not require systemd).**

## Language & dependencies

**Go.** Single static binary, no runtime/interpreter, low idle memory —
a good fit for the "runs on a potato" priority. The standard library
covers almost everything:

| Need | Package |
|---|---|
| JSON state files | `encoding/json` |
| Content hashing | `crypto/sha256` |
| Glob matching (`.ignore`, `tag-bulk --pattern`) | `path/filepath` (`filepath.Match`) |
| Running the wallpaper backend | `os/exec` |
| Scheduling / sleep | `time` |
| Weighted random draw | `math/rand/v2` + a small cumulative-sum helper (no stdlib equivalent of a weighted choice; ~10 lines) |
| CLI subcommands | `flag` with one `flag.FlagSet` per subcommand and a small hand-written dispatcher on `os.Args[1]` |

The only external dependency is **`github.com/BurntSushi/toml`** for the
config file. TOML (rather than JSON) is kept for the config specifically
because the generated default config relies on comments (section 8).
Don't add a CLI framework (e.g. cobra) — the subcommand set is small
enough for `flag.FlagSet`, and it keeps the dependency list at one.

**Code style:** descriptive names. Go convention of no `Get` prefix on
accessors applies (`ScreenTime()`, not `GetScreenTime()`).

**Suggested layout:**

```
yarwm/
  go.mod
  main.go                 # subcommand dispatch only
  internal/
    paths/                # XDG paths for every file below
    config/               # config.toml loading, defaults, first-run template
    jsonfile/             # atomic read/write helpers for the JSON files
    filelock/             # exclusive lock so the daemon and CLI never write over each other
    library/              # scanning, .ignore handling, content hashing
    tags/                 # tags.json, quality filter, bulk tag
    history/              # history.json, buckets, scoring formula
    selection/            # selection_state.json, browse pointer, rotation flow
    backend/              # {path} substitution + exec
    daemon/               # clock-aligned loop
  cmd/migrate/main.go     # one-off migration (section 2) — separate binary, delete after use
```

## 1. Wallpaper tagging (quality + frequency)

Each wallpaper gets two independent, manually-assigned integer tags
(suggested range 1-10 for both, adjust if needed):

- **`quality`** — a pure **filter**, not part of the scoring math at all.
  Used to restrict the candidate pool before selection runs (e.g. "only
  consider quality 7+", or an exact match, or a min/max range — filter mode
  is a config/CLI setting). This replaces the user's old "quality-N nested
  directories" scheme, which only supported "N and above" filtering — the
  new system must support exact, min, max, and range filtering.
- **`frequency`** — the value that actually drives how often a wallpaper is
  picked once it's passed the quality filter (see scoring in section 4).
  Independent of quality: a low-quality-but-liked image can have high
  frequency, and vice versa.

Storage:
- JSON file keyed by file content hash (e.g. SHA-256), not filename or path
  — must survive the user freely moving files between directories under
  `library_path` for organizational purposes.
  - Suggested location: `~/.config/yarwm/tags.json`
  - Structure:
    `{ "<sha256>": { "quality": <int>, "frequency": <int>, "cache_path": "<last known path>" } }`
    (keep `cache_path` as a cache/hint only — always re-resolve/verify against the
    live filesystem, don't trust it blindly if the file moved).
- `tag [<file>|current|last|next] [--quality N] [--frequency N]` — sets/
  updates either or both values for a single wallpaper. If no target is
  given, defaults to `current`. `current`/`last`/`next` are keyword
  references, not literal filenames — see "Tag target keywords" below for
  how each resolves. A dedicated single-file tag tool is worth having even
  though bulk editing the JSON directly is already possible — see "Bulk
  tag" below for the reasoning on why both are worth building.

**Tag target keywords.** All three read directly from a small
`selection_state` file (see "Selection state" under section 7) instead of
scanning the tags/history JSON — no reason to read through 600 entries to
answer "what's current":
- `current` — `selection_state.recent[0]`, whatever's on screen right now.
- `last` — `selection_state.recent[1]`, whatever was on screen immediately
  before `current`. Same position `previous`/`undo` (no argument,
  section 7) move the cursor to.
- `next` — `selection_state.next`, the precomputed next wallpaper (see
  section 7's "Selection state"), recomputed first if its fingerprint is
  stale.

**Bulk tag.** Originally dismissed as unnecessary since the tags file is
just JSON and scriptable with `jq` — but a real, common use case makes a
dedicated tool worth it: retagging a filtered set of existing wallpapers
(e.g. "everything currently quality 4 and frequency 2, bump to frequency
3") is fiddly to express correctly in raw `jq` and easy to get wrong on
600 files. A `tag-bulk` subcommand with independent filter and target
options:

```
yarwm tag-bulk --pattern "*.jpg" \
  --filter-quality 4 --filter-frequency 2 \
  --set-quality 5 --set-frequency 3
```

- **Filters** (all optional, combine with AND): `--pattern` (glob against
  the file path), `--filter-quality` / `--filter-quality-min` /
  `--filter-quality-max`, `--filter-frequency` / `--filter-frequency-min` /
  `--filter-frequency-max` — mirrors the exact/min/max shape the main
  quality filter already uses (section 6), for consistency.
- **Targets**: `--set-quality N` and/or `--set-frequency N` — only the
  fields given are changed, whichever isn't specified stays untouched on
  matched entries.
- Show a match count and require confirmation before applying (or accept
  `--yes` to skip it for scripted use) — this is a mass mutation across
  however many files match, worth a sanity check before committing, same
  spirit as the forced-rebucket warning in section 6.

## 2. Migration (one-off, disposable)

Provide a **separate standalone program** (`cmd/migrate`, built as its own
binary), not a subcommand of the main tool, that ingests the user's existing directory structure (`quality-1/`,
`quality-1/quality-2/`, `quality-1/quality-2/quality-3/`, etc. — nested such
that a wallpaper's *actual* quality is the deepest `quality-N` directory it
lives under) and converts it into flat `quality` tag entries in the tags
JSON (leave `frequency` unset/default, since the old scheme has no
equivalent). Being a separate program with its own `main` package means
the user can delete the `cmd/migrate/` directory entirely after running it
once, without touching the core tool. It should reuse the main module's
`internal/` packages (hashing, tags store) rather than duplicating them.

## 3. Library location & scanning

- `library_path` (config value) — root directory the tool scans for
  wallpaper images. The tool should never scan outside this path.
- `recursive` (boolean, config value) — whether to descend into
  subdirectories under `library_path`.
- Per-directory `.ignore` file — one glob pattern per line, matched
  against entry names in that directory with `filepath.Match` (no
  negation, no gitignore-style precedence — just "skip anything in this
  directory matching these patterns"). This avoids pulling in a full
  gitignore-semantics library, which would be overkill for a flat
  per-directory exclude list.

## 4. Wallpaper backend (must not be hardcoded to `awww`)

Support any wallpaper-setting program via a configurable command +
argument list, with a `{path}` placeholder substituted with the chosen
image's absolute path at call time — modeled on how Matugen configures
its own wallpaper command:

```toml
[wallpaper_command]
command = "awww"
arguments = ["img", "{path}", "--transition-type", "grow"]
```

This should work equally for `awww`, `swww`, `hyprctl hyprpaper reload`,
`feh --bg-fill`, etc. — the tool just does subprocess substitution and
invocation, no backend-specific logic.

## 5. Scheduling

- No systemd dependency. All state the tool needs (tags, history) already
  lives in JSON, so there's no benefit to systemd's persistence/integration
  features here, and requiring it would break portability to non-systemd
  distros (Alpine, Artix, Void, etc.).
- Implement as a **simple long-lived loop process**: compute time until the
  next aligned tick, sleep, fire, repeat. A sleeping process uses ~0% CPU
  between ticks (the OS wakes it via a timer rather than polling), so this
  is lighter-weight than a systemd timer for this use case.
- Interval unit is **seconds** (float, so sub-second/ms-level intervals are
  just e.g. `0.5`) — ticks align to the interval counted from midnight
  (e.g. interval=600 fires at 00:00:00, 00:10:00, 00:20:00; interval=5
  fires every 5 seconds on the clock, i.e. :00, :05, :10 seconds of every
  minute). Must self-correct if started mid-interval — compute
  `sleep_seconds = interval - (seconds_since_midnight % interval)` on
  startup and after every tick.
- At very short intervals, the real bottleneck becomes how fast the
  configured wallpaper backend can actually decode and swap an image — not
  this tool's scheduling precision.
- Launch via Hyprland's `exec-once` (or equivalent for other compositors/
  window managers) rather than a system service. Tradeoff versus systemd:
  no automatic restart-on-crash, acceptable for a tool this simple; a
  tiny restart wrapper could be added later if desired.
- Read the tags/history JSON once at startup and only re-read on file
  change (not every tick) to keep per-tick CPU cost negligible even at
  short intervals.

## 6. Selection algorithm

Maintain a history file per wallpaper (keyed by the same content hash used
for tags), e.g. `~/.local/state/yarwm/history.json`. Store
**bucketed screen-time totals**, not one entry per rotation — with short
intervals (seconds/ms), a raw per-event log can reach millions of entries
and hundreds of MB in memory. Bucketing bounds memory regardless of
interval length, and is controlled by two independent config values:

- `screen_time_days_per_bucket` — size of each bucket, in days (default: `1`).
- `screen_time_max_days` — how far back screen-time counts toward the
  score, in days (default: `30`).

Number of buckets kept per wallpaper = `ceil(screen_time_max_days /
screen_time_days_per_bucket)` — 30 buckets at the defaults above (previously 5,
at 7-day buckets — see the memory-scaling numbers in section 10, still
trivial at these sizes). Both values are plain numbers of days rather than
a fixed granularity choice, so they can be tuned independently (e.g. finer
buckets for more resolution, or a longer window, without one forcing a
change to the other).

**Handling `screen_time_days_per_bucket` / `screen_time_max_days` changes.**
By default, **do nothing to existing stored buckets when either value
changes** — this avoids any data loss or approximation entirely, which is
the simplest and safest default:

- Old buckets stay exactly as they are, at whatever size they were created
  with. They still get pruned normally once they fall entirely outside
  `screen_time_max_days` — nothing special there.
- New show events use the *current* `screen_time_days_per_bucket` going
  forward, so a wallpaper's history can end up with a handful of
  differently-sized buckets after a config change (some old and wide, some
  new and narrow). This is harmless: `screen_time(wallpaper)` is just a sum
  over whatever buckets currently exist within the window, and that sum is
  exactly correct regardless of whether the buckets are a uniform size —
  bucket *count* was only ever about bounding memory, never about
  correctness, so there's no need to force it back to the "expected" count
  at all.
- A `--force` flag on a maintenance/rebucket command triggers an *actual*
  consolidation pass that resamples all of a wallpaper's (or the whole
  library's) buckets into the current config's exact bucket layout. This is
  the one path where data actually gets rewritten under an assumption, so
  it's the one path that needs a warning: merging into fewer, wider buckets
  is always exact (sum of what's inside), but splitting into more, narrower
  buckets has no record of *when within* an old bucket its time was
  accumulated, so it has to be redistributed under an assumption — treat
  each old bucket's total as a uniform daily rate
  (`total_seconds / bucket_length_days`), then for each new bucket sum
  `rate × overlapping_days` across whatever old buckets it overlaps. Total
  screen-time is always conserved either way; only the *split* direction is
  inventing information about timing, and only `--force` triggers a split
  at all — so warn and require confirmation specifically when a forced
  rebucket would split, not on ordinary config changes and not on forced
  merges.

```json
{
  "<sha256>": {
    "last_shown": <unix_timestamp or null>,
    "screen_time_buckets": { "<bucket_start_date>": <total_seconds_shown>, ... }
  }
}
```

Each rotation:
1. **Persist `last_shown` immediately when a new wallpaper is set**, not
   deferred until the next tick's close-out step — this matters for crash/
   power-loss recovery (see "Robustness" below).
2. **Close out the previous show event** — before picking a new wallpaper,
   compute `duration = now - previous_wallpaper's last_shown` and add it
   to that wallpaper's bucket covering `last_shown` (creating the bucket
   if needed), then drop any of that wallpaper's buckets that have fallen
   entirely outside `screen_time_max_days` — this keeps the bucket
   count naturally capped at all times, no separate pruning/retention
   setting needed. This is why duration (time-on-screen), not a raw show
   count, is tracked — a raw count would be skewed if the interval length
   changes over time (e.g. switching from 10-minute to 10-second rotations
   would inflate counts without meaning "seen more"); duration stays
   meaningful regardless of interval changes.
3. **Filter by quality** — restrict the candidate pool to wallpapers
   matching the active quality filter (exact/min/max/range, config or CLI
   override). Quality plays no further role after this point.
4. **Score the filtered pool:** (formula names below are written in
   snake_case for readability in this spec; in Go they become
   `frequencyWeight`, `ageFactor`, `screenTime`, `freshnessFactor`,
   `score` — use `math.Pow` for the exponentials.)

```
frequency_weight(frequency)  = base_f ^ frequency
                             # PURE exponential — frequency 10 is always
                             # strictly the heaviest weight, no plateau.
                             # base_f is a config value (pick a reasonable
                             # default, e.g. 1.5-2, document how changing
                             # it affects the curve).

age_factor(wallpaper)        = time_since_last_shown(wallpaper)
                             # linear in elapsed time since last shown.
                             # If never shown, use a large constant (or
                             # treat as "oldest possible" so new additions
                             # get an initial boost) rather than infinity.

screen_time(wallpaper)       = sum of `screen_time_buckets` values within
                                `screen_time_max_days`
                             # buckets naturally age out and get dropped
                             # once fully outside the window (step 2
                             # above), so this is always a simple sum of
                             # whatever's currently stored.

freshness_factor(wallpaper)  = decay_f ^ (screen_time(wallpaper) / decay_scale_seconds)
                             # decay_f < 1 (config value, e.g. 0.7).
                             # `decay_scale_seconds` converts screen time
                             # (raw seconds) into a reasonable exponent
                             # scale (e.g. 3600, i.e. one hour of
                             # screen-time per decay step), also a config
                             # value.
                             # Purpose: a wallpaper that's spent a lot of
                             # time on screen recently should score lower
                             # than one that hasn't, even if the latter is
                             # objectively older — screen-time within the
                             # window matters more than raw age here.
                             # Never hits exactly zero.

score(wallpaper) = frequency_weight(frequency) × age_factor(wallpaper) × freshness_factor(wallpaper)
```

5. **Weighted-random draw** across the filtered pool using `score` as the
   weight — NOT an argmax/highest-score pick. Should feel "mostly random,
   but not exactly," where frequency, staleness, and screen-time all
   nudge the odds without making anything deterministic or excluding any
   wallpaper outright.

**Robustness (power loss / crash).** If the machine is shut down or the
process crashes, the "close out the previous show event" step (2, above)
never gets to run for whatever wallpaper was on screen at the time — its
trailing screen-time would otherwise be silently lost, and there'd be no
record of when it started being shown. This is exactly why step 1 writes
`last_shown` to disk *at selection time*, immediately, rather than only
recording it as part of the later close-out: as long as `last_shown` for
the currently-displayed wallpaper is always on disk, the next time the
tool runs (after a reboot, whenever that is) it can still close out that
wallpaper's screen-time correctly using `now - last_shown` before picking
the next one — no separate crash-recovery logic needed beyond writing
`last_shown` eagerly instead of batching it. (Note: this counts wall-clock
time regardless of whether the machine was actually on/awake during that
span — distinguishing sleep/suspend/shutdown from genuine screen-on time
would need OS-level suspend hooks, e.g. systemd-logind's `PrepareForSleep`
signal, which is a reasonable future enhancement but out of scope here.)

Library size to design for: ~600 images.

Config values to expose (e.g. small TOML/YAML/JSON config file): interval
(seconds), `library_path`, `recursive`, `base_f`, `screen_time_days_per_bucket`,
`screen_time_max_days`, `decay_f`, `decay_scale_seconds`, `skip_penalty_seconds`,
`history_depth`, default
quality filter, wallpaper backend command + arguments.

## 7. CLI subcommands

**Two families of cursor movement, both non-mutating on their own** — see
"Selection state" below for the shared mechanism. What differs between them
is only what happens the *next time a real rotation event fires* (the
automatic tick, or a forward move with nothing left to walk to) while the
cursor isn't at `recent[0]`:

- `previous [N]` / `next [N]` — the "patient" pair. Move the cursor
  without touching history or the ring buffer. If you leave the cursor
  away from `0` and a real rotation fires (the scheduler ticking, or
  calling `next` again with nothing left ahead), it does **not** discard
  anything — it just advances the cursor one step toward `0`, same as an
  implicit single `next`. Real generation only resumes once the cursor is
  actually back at `0`. So walking back and just leaving it lets the
  normal schedule gently carry you back to "now" over subsequent ticks,
  nothing lost.
- `undo [N]` / `redo [N]` — the "ephemeral" pair. Same cursor mechanism,
  but if the cursor is left away from `0` and a real rotation fires, it
  **clamps** immediately instead: whatever `recent[browse_pointer]`
  currently is becomes the new `recent[0]`, everything between old
  `recent[0]` and that point is dropped from the ring buffer, and fresh
  content generates right away — peeking at something and then letting
  real time move on abandons the peek rather than walking back to it.
- Either pair, moving backward (`previous`/`undo`) never generates
  anything — there's no "fall off the edge" going backward, only forward.
  Moving forward with nothing left to walk to is what triggers the
  distinction above.
- Clamping never touches the already-recorded screen-time in
  `history.json` for the dropped wallpapers — that already happened and
  stays correct for scoring. It only trims the small navigation buffer,
  i.e. which positions are still reachable by walking/peeking forward.
- `skip` always clamps immediately, regardless of what
  `clamp_on_next_rotation` currently holds — skip is a decisive "not this
  one," not patient browsing, so it doesn't make sense for it to gently
  respect an in-progress walk.
- `clamp` — manually commits the current cursor position as the new
  `recent[0]` (same clamp logic as above) *without* also generating new
  content — useful when you've `undo`'d or `previous`'d to something you
  like and want it to become the real current without also picking
  something new on top of it, which is what `next`/`redo` falling into
  real generation would do instead.
- `pause` / `resume` — do NOT stop the loop process for this. Instead, use
  a state file (e.g. `~/.local/state/yarwm/paused`) that a rotation checks
  first — if present, log and exit without changing anything. The loop
  keeps ticking on schedule (preserving alignment) but no-ops while
  paused. Manual commands still work even while paused (explicit manual
  action overrides the pause).
- `tag` / `tag-bulk` — see section 1 for full detail (single-target with
  `current`/`last`/`next` keyword support, and pattern+filter-based bulk
  retagging).
- Any command that ends up triggering real generation (`next`, `redo`,
  `skip`, or an automatic tick — see "Selection state" below) accepts an
  optional quality filter override (e.g. `--quality-min 7`) — applies
  once it reaches the point of actually generating fresh content, not to
  plain cursor movement. Fallback chain, in order:
  1. Explicit filter given on this invocation → use it, and save it as the
     new last-used filter.
  2. No filter given → use the last-used filter, if one has ever been
     saved.
  3. No last-used filter saved yet → use the configured default filter
     from the config file.
  The last-used filter is stored in a small plain state file, e.g.
  `~/.local/state/yarwm/session_filter` — the same kind of
  file as tags/history, just persisted directly rather than tied to any
  process's lifetime. Every `next` invocation that actually
  triggers generation (automatic tick inside the daemon, or a manual call
  from the terminal — each a separate OS process) just reads this one
  file for the fallback and writes to it when an explicit filter is
  given. No daemon/CLI communication needed at all.
- The **daemon startup** command (whatever launches the long-running loop)
  should accept the same optional quality filter override (e.g.
  `yarwm start --quality-min 7`). If given, it follows the
  identical rule as `next`: write it to `session_filter`
  immediately on startup, so it becomes the fallback for both automatic
  ticks and any bare `next` calls until it's changed again or the
  daemon restarts. If no
  filter is given at startup, leave `session_filter` untouched (don't
  overwrite an existing value, and don't create one) — startup with no
  filter shouldn't reset a previously-set session filter.
- `time_left` — two output forms: a numeric one (seconds remaining until
  the next scheduled tick, `--seconds`) and a human-readable one (e.g.
  "4m 12s", the default). Write a tiny h/m/s formatter by hand rather
  than using `time.Duration.String()` directly, which prints forms like
  "4m12.345s".
- `query_next_image` — prints the path of the precomputed next wallpaper
  (see "Selection state" below) without side effects; if it detects
  the relevant config has changed since that value was computed, it
  recomputes fresh before printing.
- `status` — a plain-text summary of runtime state, read entirely from
  `selection_state` plus a couple of other already-existing small state
  files (no new files needed for this):
  - **Current**: `recent[0]`'s path, plus its `quality`/`frequency` tags
    (from `tags.json`).
  - **Last**: `recent[1]`'s path, if `history_depth` allows one.
  - **Next**: `next.cache_path` — the precomputed pick, shown as-is (this
    tool has no reason to hide it as a surprise, it's a personal utility).
  - **Browsing**: if `browse_pointer != 0`, show the pointer's position
    and — since `clamp_on_next_rotation` answers this directly — whether
    the next rotation will clamp or gently walk back. Omit this section
    entirely when `browse_pointer == 0`, since there's nothing to report.
  - **Active quality filter**: read from `session_filter` (the
    quality-filter fallback chain above) if set, otherwise the configured
    default.
  - **Paused**: yes/no, from the `paused` state file.
  - **Time left**: reuse `time_left`'s own logic directly (both the
    numeric and human-readable forms) rather than duplicating it.
  No config dump needed beyond the active quality filter — the rest of
  `status` is about *current runtime state*, not static configuration,
  which the user can already read straight from the config file.

**Selection state.** A single small file, e.g.
`~/.local/state/yarwm/selection_state.json`, tracks recent show history and
the precomputed next pick together — this is the one thing every command
that needs "which wallpaper" (`status`, `tag current/last/next`,
`previous`/`next`, `undo`/`redo`,
`query_next_image`) reads, instead of each re-deriving it by scanning the
tags/history JSON for a single value:

```json
{
  "recent": [
    { "hash": "<sha256>", "cache_path": "<path>" },
    { "hash": "<sha256>", "cache_path": "<path>" }
  ],
  "next": { "hash": "<sha256>", "cache_path": "<path>", "snapshot_fingerprint": "<hash>" },
  "browse_pointer": 0,
  "clamp_on_next_rotation": false
}
```

`recent` is a small **bounded ring buffer**, most-recent-first —
`recent[0]` is `current`, `recent[1]` is one step back (what `last`
resolves to), `recent[2]` two steps back, and so on, capped at
`history_depth` entries (config value, default e.g. `10` — this is for a
handful of steps of back-navigation, not an audit log; an *unbounded*
sequential log would reintroduce the exact unbounded-growth problem
bucketing was built to avoid in section 6, so this stays deliberately
small). `recent` only ever contains what was *actually shown* — the
tentative `next` pick never enters it unless/until real generation
actually happens.

`clamp_on_next_rotation` is a plain boolean, not a record of which command
ran — this is a deliberate architecture choice, not just a naming one:
each browse command sets it directly to whatever's correct for *itself*
the moment it runs (`undo`/`redo` set it `true`, `previous`/`next` set it
`false`), so the rotation logic never needs to know command names or
"families" at all — it just reads one boolean. That keeps the clamp
*policy* decision inside the browse commands (where it belongs, since
that's the thing that knows which kind of browsing just happened) rather
than duplicated as a lookup table inside the rotation logic. It also
happens to be exactly the question a `status` command wants to answer
directly ("will the next rotation clamp your history?"), rather than
making the user infer it from a command name.

`next.snapshot_fingerprint` is a snapshot of whatever config/library state
`next.cache_path` was computed from (e.g. a hash of the active config
values + tags file mtime + history file mtime). It lives nested inside
`next`, not at the top level — its only job is answering "is this
precomputed pick still valid," which is a `next`-specific concern, so it
belongs grouped with the thing it validates rather than floating as a
sibling field a reader has to mentally connect back to `next` themselves.

This also solves precomputation, which was the original motivation: to
keep a real rotation's critical path at effectively zero added latency
(the wallpaper backend's own decode/transition time becomes the only
bottleneck), the weighted-random pick isn't computed synchronously when a
rotation is due — it's precomputed ahead of time and just sitting in
`next` already.

- **`previous [N]` / `undo [N]`** (default `N=1`): move
  `browse_pointer` back by `N` (capped at `history_depth - 1`), set
  `clamp_on_next_rotation` to `false`/`true` respectively, and hand
  `recent[browse_pointer].cache_path` to the backend. Nothing else changes
  — no history close-out, no ring-buffer mutation. Never generates
  anything (there's no "past the end" going backward).
- **`next [N]` / `redo [N]`** (default `N=1`): if moving
  forward by `N` leaves the resulting `browse_pointer >= 0`, this is also
  just cursor movement + a backend display call, `clamp_on_next_rotation`
  set to `false`/`true` respectively, nothing else touched. If it would
  move past `0` (nothing left to walk/peek to), a **real rotation**
  happens instead — see below.
- **Real rotation** (an automatic tick firing, or a forward command
  hitting the point above): read `selection_state`.
  - If `browse_pointer == 0` (nothing was being browsed): proceed exactly
    as before — compute a fresh snapshot fingerprint; if it matches
    `next.snapshot_fingerprint`, hand `next.cache_path` straight to the
    backend immediately (the whole reason latency drops to ~0, the pick
    was already done); otherwise recompute fresh. *Only after* handoff:
    close out `recent[0]`'s history (section 6, step 2), push the used
    pick onto the front of `recent` (dropping the oldest past
    `history_depth`), compute the *following* pick, and write it as the
    new `next` object (`hash`, `cache_path`, and its fresh
    `snapshot_fingerprint` together).
  - If `browse_pointer != 0` and `clamp_on_next_rotation == false`:
    **don't** clamp — just move `browse_pointer` one step toward `0` and
    display `recent[browse_pointer]`. No history close-out, no
    generation, no hash check. Real generation only resumes on a later
    rotation once the pointer naturally reaches `0` this way.
  - If `browse_pointer != 0` and `clamp_on_next_rotation == true` (or
    `skip` was called, which always takes this branch regardless of the
    stored value): **clamp** — `recent[browse_pointer]` becomes the new
    `recent[0]`, everything between old `recent[0]` and that point is
    dropped from `recent` (this only trims the navigation buffer, it
    never touches already-recorded screen-time in `history.json`),
    `browse_pointer` resets to `0`, `clamp_on_next_rotation` resets to
    `false`, and generation proceeds immediately as in the first case
    above.
- `clamp` — runs just the clamp step above (if `browse_pointer != 0`)
  without the generation step, i.e. commits wherever you've browsed to as
  the new `recent[0]` without also picking something new on top of it.
- `query_next_image` reads `selection_state.next` and applies the same
  fingerprint check, so it can be polled cheaply at any time without
  affecting the daemon's own state.
- Running the "compute the following pick" step in parallel with the
  backend call (rather than strictly after it returns) was considered —
  only worth doing if it's genuinely trivial to add (e.g. a single
  fire-and-forget background thread), since the scoring pass is already
  sub-millisecond and unlikely to be worth the added complexity of real
  concurrency for the gain involved.

## 8. Zero-config defaults

Running bare `yarwm` with no config file at all should work — every
config value needs a sane built-in default, with one deliberate exception:

- `recursive`: `true`
- `library_path`: a conventional fallback, e.g. `$(xdg-user-dir
  PICTURES)/Wallpapers` (or `~/Pictures/Wallpapers` if that helper isn't
  available) — won't necessarily point at the user's real library on a
  fresh install, but means the tool starts up and reports "no images
  found" rather than erroring on a missing config.
- `interval`: a reasonable rotation interval, e.g. `600` seconds (10 min).
- `base_f`: `1.5`–`2` (pick one, document it).
- `screen_time_days_per_bucket`: `1`, `screen_time_max_days`: `30` (see
  section 6).
- `decay_f`: `0.7`, `decay_scale_seconds`: `3600`.
- `skip_penalty_seconds`: a config value with its own default (pick
  something clearly noticeable relative to a typical interval, e.g. equal
  to a few intervals' worth of time).
- `history_depth`: `10` (a handful of back-navigation steps, not an audit
  log — see "Selection state," section 7).
- Default quality filter: none (all qualities eligible) — matches
  "everything just works" better than silently filtering out untagged
  images (which would default to lacking a quality tag entirely, and
  should be treated as always-eligible unless the user opts into
  filtering).

**The one exception: the wallpaper backend command.** There's no safe
universal default here — it genuinely depends on the user's setup. On
first run with no backend configured, **warn the user clearly and
generate a config file with the backend section commented out**,
containing reference examples for `awww` and `hyprpaper` (the two
scenarios this spec was written around):

```toml
# No wallpaper backend is configured yet — yarwm can't set a wallpaper
# until you uncomment and fix one of these (or write your own).
# These are reference examples only, captured at the time this file was
# generated — yarwm does NOT keep them updated against future breaking
# changes in awww/hyprpaper's own CLI syntax. Verify against their current
# docs before relying on either.
#
# [wallpaper_command]
# command = "awww"
# arguments = ["img", "{path}", "--transition-type", "grow"]
#
# [wallpaper_command]
# command = "hyprctl"
# arguments = ["hyprpaper", "reload", ",{path}"]
```

This keeps the generated config honest about being a snapshot rather than
something yarwm silently maintains compatibility for — exactly the same
reasoning as the "keep old buckets by default" approach in section 6:
don't invent/maintain something on the user's behalf that might go stale
without them knowing.



## 9. State storage: JSON, not a database

~600 records comfortably fit in memory as plain Go maps/structs. SQLite was
considered and rejected as overkill: scoring needs to scan the *whole*
filtered pool every tick anyway, so a database wouldn't save a query — the
full data still needs to end up in application code either way. Revisit
only if the library ever grows into the tens of thousands.

## 10. Performance expectations (for reference, not something to re-derive)

- Idle CPU usage between ticks: effectively 0% — a sleeping process is
  woken by the OS timer, it does not poll.
- Per-tick cost (score ~600 items, weighted-random draw): sub-millisecond,
  trivial even on modest/old hardware — as long as the JSON is read once at
  startup and only re-read on file change, not re-parsed from disk every
  tick.
- The only meaningfully CPU/GPU-heavy step is the external wallpaper
  backend itself decoding the image and rendering the transition — that
  cost is identical regardless of this tool's language or scheduling
  approach, and isn't something this design controls.
- Memory: the full tags file and the bucketed history load into memory at
  startup. Two things worth checking directly rather than assuming, both
  measured with a Python dict-of-buckets prototype — Go structs and maps
  are more compact, so treat these as upper bounds:

  **Buckets per wallpaper**, fixed at 600 wallpapers (the earlier
  bucket-count sweep, kept for reference — note the default moved from 5
  buckets to 30 since this was first measured, see the second table below
  for that):

  | buckets/wallpaper | total memory (600 wallpapers) |
  |---:|---:|
  | 1 | ~0.05 MB |
  | 3 | ~0.16 MB |
  | 5 | ~0.27 MB |
  | 10 | ~0.55 MB |
  | 50 | ~2.7 MB |
  | 100 | ~5.5 MB |
  | 500 | ~27 MB |
  | 1,000 | ~55 MB |
  | 5,000 | ~274 MB |

  **Library size**, fixed at 30 buckets/wallpaper (the current default:
  `screen_time_days_per_bucket=1`, `screen_time_max_days=30`):

  | wallpapers | total memory (30 buckets each) |
  |---:|---:|
  | 100 | ~0.27 MB |
  | 300 | ~0.82 MB |
  | 600 (the actual library size) | ~1.6 MB |
  | 1,000 | ~2.7 MB |
  | 2,000 | ~5.5 MB |
  | 5,000 | ~13.7 MB |
  | 10,000 | ~27.4 MB |

  So yes, the 1-day/30-day default (30 buckets) checks out fine — even at
  10,000 wallpapers (way beyond the ~600 this was designed for) it's still
  under 30MB. Tags file adds a flat ~0.2MB on top, roughly independent of
  bucket count. In short: it takes on the order of **hundreds to
  low-thousands of buckets per wallpaper**, or **tens of thousands of
  wallpapers** at 30 buckets each, before this becomes a real number on
  modest hardware — nowhere near what any reasonable
  `screen_time_days_per_bucket` / `screen_time_max_days` setting would produce.
  This is also why bucketing matters at all in the first place —
  the *raw per-event* log this replaced, at a 5-second rotation interval
  over a 6-month window, measured at ~580MB, which would be a real problem
  on low-end hardware; bucketing avoids that regardless of how the two
  config values are tuned.

## 11. Open items for you to decide during implementation

- Default values for `base_f`, `decay_f`, `decay_scale_seconds`,
  `skip_penalty_seconds` (starting points suggested in section 8's
  zero-config defaults — tune from there).
- Whether multi-monitor setups need distinct wallpapers per output or a
  single shared wallpaper (not specified — ask if it affects the design
  significantly, otherwise assume single/shared).
- Confirm current `awww` CLI invocation/flags for the default
  `wallpaper_command` config example (it may differ from `swww`, which
  `awww` is modeled after).
