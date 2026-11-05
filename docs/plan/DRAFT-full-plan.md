# Implementation plan

> [!WARNING]
> **DRAFT — NOT REVIEWED. Do not implement from this file.**
>
> This is the whole plan in one place, kept only so the overall structure
> can be seen while the phases are reviewed one at a time. The reviewed
> version of each phase is its own file in this directory
> ([README](README.md)); where they differ, the phase file wins.
>
> **Delete this file as soon as possible** — at the latest in the pull
> request that adds the last phase file.

This breaks [`spec.md`](../spec.md) into small steps. Each step is one feature
branch and one pull request, small enough to finish in a sitting, and ends
with a green `make check`. Steps are ordered so every one builds only on
what came before.

- [How to work through a step](#how-to-work-through-a-step)
- [Conventions](#conventions)
- [Decisions](#decisions) — gaps in the spec, filled in here
- [Overview](#overview)
- Steps: [1. Foundations](#phase-1--foundations) ·
  [2. Library and tags](#phase-2--library-and-tags) ·
  [3. Choosing a wallpaper](#phase-3--choosing-a-wallpaper) ·
  [4. Rotation](#phase-4--rotation) ·
  [5. Daemon](#phase-5--daemon) ·
  [6. Browsing and extras](#phase-6--browsing-and-extras)

## How to work through a step

1. Branch from an up-to-date `dev`: `git switch dev && git pull && git switch -c <branch>`.
2. Read the step and the spec sections it points to.
3. Write the tests listed under **Tests** first (or alongside), then the code.
4. `make check` must pass; then do the **Try it** check if the step has one.
5. Open a pull request into `dev` titled with the step's **Commit** line,
   and squash-merge it once CI is green (see `CONTRIBUTING.md`).

Signatures in the steps are suggestions that fit together across steps —
keep them unless you have a reason, and if you change one, update the
later steps that use it.

## Conventions

- **Packages** live under `internal/` (see the layout in the spec). CLI
  commands live in `internal/cli`, one file per command; `main.go` only
  calls `cli.Run`.
- **Dependency injection for time, randomness and the backend.** Code
  never reaches for them itself; it receives them as parameters, so tests
  can pass fixed ones: the current time (`now time.Time` or
  `now func() time.Time`), the random source (`*rand.Rand` from
  `math/rand/v2`, seeded in tests with `rand.New(rand.NewPCG(1, 2))`), and
  the wallpaper backend (an interface, faked in tests).

    ```go
    func Rotate(now time.Time, random *rand.Rand, display Displayer) error // testable
    func Rotate() error // calls time.Now() inside: a test can't control it
    ```

- **Comments** follow the comment rule in `CONTRIBUTING.md`. The comments
  inside this plan's code snippets are spec for you, the implementer —
  don't copy them into the code.
- **Tests never touch your real files.** Every test that reads or writes
  state calls `test.Setenv("XDG_CONFIG_HOME", test.TempDir())` and the same
  for `XDG_STATE_HOME`, and builds libraries under `test.TempDir()`.
- **Table-driven tests** for anything with more than two cases.
- **Errors**: wrap with context (`fmt.Errorf("reading %s: %w", path, err)`);
  the CLI prints them as `yarwm: <message>` on stderr and exits 1 (usage
  errors exit 2).
- **Running for real**: the dev container is for building and testing.
  Real use happens on the host with the built binary (`make build`, then
  `./build/yarwm ...`), because only the host has your wallpapers, your
  `~/.config` and the wallpaper backend.

## Decisions

The spec leaves these open. Each is filled in here so no step has to guess;
the step that depends on it is listed. Change any of them before that step
starts, and fold them into `spec.md` once settled.

| #   | Topic                          | Decision                                                                                                                                                                                                                                                                                                                                                                                                 | Used in |
| --- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| D1  | Tag values                     | `quality` and `frequency` are integers 1–10; anything else is rejected                                                                                                                                                                                                                                                                                                                                   | 10      |
| D2  | Untagged frequency             | A wallpaper with no `frequency` counts as **5** (the middle)                                                                                                                                                                                                                                                                                                                                             | 10, 16  |
| D3  | Untagged quality               | Eligible when no quality filter is active; excluded by any active filter (spec §8)                                                                                                                                                                                                                                                                                                                       | 16      |
| D4  | `base_f` default               | **2** — each frequency point doubles the odds                                                                                                                                                                                                                                                                                                                                                            | 5       |
| D5  | `skip_penalty_seconds` default | **1800** (three default intervals)                                                                                                                                                                                                                                                                                                                                                                       | 5       |
| D6  | Never-shown age                | A wallpaper never shown counts as last shown `screen_time_max_days` ago (30 days by default): a strong but finite boost                                                                                                                                                                                                                                                                                  | 15      |
| D7  | Repeats                        | The wallpaper on screen is excluded from the pool, unless it's the only candidate                                                                                                                                                                                                                                                                                                                        | 16      |
| D8  | Library rescans                | The library (directory listing + `stat`) is rescanned before every pick. Content hashes are cached in a **`library_index.json`** state file (path → size, mtime, hash), so only new or changed files are hashed                                                                                                                                                                                          | 9, 21   |
| D9  | Concurrent writes              | The daemon and CLI commands are separate processes writing the same files. Every state change holds an exclusive lock on a `lock` file in the state directory (`flock`) for its whole read-modify-write                                                                                                                                                                                                  | 4, 11+  |
| D10 | Corrupt state files            | A JSON file that fails to parse is an **error**, never silently replaced (replacing it would wipe the data)                                                                                                                                                                                                                                                                                              | 3       |
| D11 | Midnight                       | Tick alignment counts from **local** midnight                                                                                                                                                                                                                                                                                                                                                            | 24      |
| D12 | Buckets                        | Keys are UTC dates (`2006-01-02`); bucket starts are aligned to the Unix epoch in `screen_time_days_per_bucket` steps. A show's whole duration goes to the bucket containing its start. A bucket counts toward screen time — and survives pruning — while its **start** is within `screen_time_max_days` of now. Screen time filters by the window when reading, since pruning only happens on close-out | 14      |
| D13 | Daemon start                   | `yarwm start` re-displays `recent[0]` right away if there is one (the screen is usually blank after login) without counting it as a rotation; otherwise it does a real rotation. Then it waits for the next aligned tick                                                                                                                                                                                 | 26      |
| D14 | Single daemon                  | A second `yarwm start` refuses to run while one is already running (non-blocking lock on `daemon.lock`)                                                                                                                                                                                                                                                                                                  | 26      |
| D15 | `query_next_image` when stale  | Recomputes the pick and **saves** it, so the printed path is what the next rotation shows                                                                                                                                                                                                                                                                                                                | 23, 30  |
| D16 | Bare `yarwm`                   | Prints help, as now; the daemon is `yarwm start`                                                                                                                                                                                                                                                                                                                                                         | 7       |
| D17 | Backend calls                  | No shell; `{path}` is replaced inside every argument; wait for exit with a 30-second timeout; a non-zero exit is an error carrying stderr                                                                                                                                                                                                                                                                | 17      |
| D18 | Quality filter flags           | `--quality N`, `--quality-min N`, `--quality-max N` on `next`, `redo`, `skip` and `start`. In the config: a `[default_quality_filter]` table with `exact`, `min`, `max`                                                                                                                                                                                                                                  | 1, 18   |
| D19 | `tag-bulk` scope and pattern   | Candidates are all wallpapers currently in the library, tagged or not. `--pattern` without `/` matches the file name; with `/`, the path relative to `library_path`. An unset quality never matches a quality filter; frequency filters use the effective frequency (D2)                                                                                                                                 | 12      |
| D20 | `rebucket`                     | `yarwm rebucket` only reports what would change; `yarwm rebucket --force` applies it, asking for confirmation when buckets would be split (`--yes` skips the prompt)                                                                                                                                                                                                                                     | 32      |
| D21 | Image types                    | `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.bmp` (case-insensitive)                                                                                                                                                                                                                                                                                                                                      | 8       |
| D22 | Monitors                       | One wallpaper shared by all monitors (spec §11 default)                                                                                                                                                                                                                                                                                                                                                  | —       |

## Overview

| Phase                   | Steps | Result                                                                                    |
| ----------------------- | ----- | ----------------------------------------------------------------------------------------- |
| 1. Foundations          | 1–7   | Building blocks: filter type, paths, JSON files, lock, config, CLI skeleton               |
| 2. Library and tags     | 8–13  | **Milestone:** tag wallpapers (`tag`, `tag-bulk`) and migrate the old `quality-N` folders |
| 3. Choosing a wallpaper | 14–18 | History, scoring, weighted pick, backend, session filter                                  |
| 4. Rotation             | 19–23 | **Milestone:** `next` / `skip` change the wallpaper by hand                               |
| 5. Daemon               | 24–27 | **Milestone:** automatic rotation → **release v0.1.0**                                    |
| 6. Browsing and extras  | 28–33 | `previous`/`undo`/`redo`/`clamp`, `status`, `rebucket`, docs → **release v0.2.0**         |

---

## Phase 1 — Foundations

### Step 1 — Quality filter type

**Branch** `feature/quality-filter` · **Commit** `feat(filter): add quality range filter` · **Spec** §1, §6 step 3 · **Decisions** D18

A filter used everywhere a quality (or frequency) range appears: config,
CLI flags, the session filter file, `tag-bulk`.

Create `internal/filter/filter.go`:

```go
// Range selects values by exact match or by an inclusive min/max.
// The zero value (all nil) matches everything.
type Range struct {
	Exact *int `toml:"exact" json:"exact,omitempty"`
	Min   *int `toml:"min"   json:"min,omitempty"`
	Max   *int `toml:"max"   json:"max,omitempty"`
}

func (r Range) IsEmpty() bool
func (r Range) Matches(value int) bool
func (r Range) Validate() error // error: Exact together with Min/Max; Min > Max
func (r Range) String() string  // "any", "5", ">= 7", "<= 3", "4-6"
```

**Tests:** empty range matches 1 and 10 · exact matches only its value ·
min only, max only, min+max (both ends inclusive) · `Validate` rejects
exact+min and min > max · `String` for each shape.

**Done when** `make check` passes.

### Step 2 — XDG paths

**Branch** `feature/paths` · **Commit** `feat(paths): add xdg file locations` · **Spec** §1, §6, §7

Create `internal/paths/paths.go` with one function per file, so no other
package builds paths itself:

```go
func ConfigDir() (string, error) // $XDG_CONFIG_HOME/yarwm, else ~/.config/yarwm
func StateDir() (string, error)  // $XDG_STATE_HOME/yarwm, else ~/.local/state/yarwm

func ConfigFile() (string, error)         // ConfigDir/config.toml
func TagsFile() (string, error)           // ConfigDir/tags.json
func HistoryFile() (string, error)        // StateDir/history.json
func SelectionStateFile() (string, error) // StateDir/selection_state.json
func SessionFilterFile() (string, error)  // StateDir/session_filter
func PausedFile() (string, error)         // StateDir/paused
func LibraryIndexFile() (string, error)   // StateDir/library_index.json  (D8)
func LockFile() (string, error)           // StateDir/lock                (D9)
func DaemonLockFile() (string, error)     // StateDir/daemon.lock         (D14)

func EnsureDirs() error // create ConfigDir and StateDir (0o755)
```

Per the XDG spec, ignore `XDG_*` values that aren't absolute paths.

**Tests** (`test.Setenv`): env var set → used · unset → home fallback ·
relative value → ignored · `EnsureDirs` creates both.

### Step 3 — JSON state files

**Branch** `feature/jsonfile` · **Commit** `feat(jsonfile): add atomic json read and write` · **Spec** §9 · **Decisions** D10

Create `internal/jsonfile/jsonfile.go`:

```go
// Read decodes path into target. A missing file is not an error:
// found is false and target is left untouched. A file that fails to
// parse is an error naming the file (D10).
func Read(path string, target any) (found bool, err error)

// Write encodes value as indented JSON and replaces path atomically:
// write a temp file in the same directory, fsync it, then os.Rename.
// Creates the parent directory if needed.
func Write(path string, value any) error
```

**Tests:** write then read round-trips · missing file → `found == false`,
no error · invalid JSON → error mentioning the path · overwriting works ·
no temp files left in the directory after `Write`.

### Step 4 — File lock

**Branch** `feature/filelock` · **Commit** `feat(filelock): add exclusive file lock` · **Decisions** D9, D14

Create `internal/filelock/filelock.go` using `syscall.Flock`:

```go
// Acquire blocks until it holds an exclusive lock on path (created if
// missing). Call release when done.
func Acquire(path string) (release func() error, err error)

// TryAcquire is Acquire without waiting: ErrLocked if someone holds it.
func TryAcquire(path string) (release func() error, err error)

var ErrLocked = errors.New("already locked")
```

Rule for every later step: **hold `Acquire(paths.LockFile())` for the whole
read → modify → write of any state file.**

**Tests:** `TryAcquire` succeeds on a free lock · a second `TryAcquire`
returns `ErrLocked` while the first is held (two opens of the same file
conflict even within one process) · succeeds again after `release`.

### Step 5 — Config: defaults and loading

**Branch** `feature/config` · **Commit** `feat(config): load config with defaults` · **Spec** §4, §6, §8 · **Decisions** D4, D5, D18

Add the TOML dependency (inside `make shell`):

```sh
go get github.com/BurntSushi/toml@latest
```

Create `internal/config/config.go`:

```go
type Config struct {
	LibraryPath             string          `toml:"library_path"`
	Recursive               bool            `toml:"recursive"`
	IntervalSeconds         float64         `toml:"interval"`
	BaseF                   float64         `toml:"base_f"`
	ScreenTimeDaysPerBucket int             `toml:"screen_time_days_per_bucket"`
	ScreenTimeMaxDays       int             `toml:"screen_time_max_days"`
	DecayF                  float64         `toml:"decay_f"`
	DecayScaleSeconds       float64         `toml:"decay_scale_seconds"`
	SkipPenaltySeconds      float64         `toml:"skip_penalty_seconds"`
	HistoryDepth            int             `toml:"history_depth"`
	DefaultQualityFilter    filter.Range    `toml:"default_quality_filter"`
	WallpaperCommand        *BackendCommand `toml:"wallpaper_command"`
}

type BackendCommand struct {
	Command   string   `toml:"command"`
	Arguments []string `toml:"arguments"`
}

func Defaults() Config
func Load(path string) (Config, error)
func (c Config) Validate() error
func (c Config) Interval() time.Duration
```

- **Defaults** (spec §8 + decisions): `library_path` =
  `$(xdg-user-dir PICTURES)/Wallpapers`, falling back to `~/Pictures/Wallpapers` (compute
  it in its own function, so tests don't depend on the machine);
  `recursive` true; `interval` 600; `base_f` 2; `screen_time_days_per_bucket`
  1; `screen_time_max_days` 30; `decay_f` 0.7; `decay_scale_seconds` 3600;
  `skip_penalty_seconds` 1800; `history_depth` 10; no quality filter; no
  wallpaper command.
- **Load** decodes the file _on top of_ `Defaults()`, so missing keys keep
  their default. A missing file returns `Defaults()`. Unknown keys are an
  error (use the decoder's metadata `Undecoded()`), so typos don't pass
  silently. Expand a leading `~/` in `library_path`.
- **Validate**: `interval` > 0; `base_f` > 1; `0 < decay_f < 1`;
  `decay_scale_seconds` > 0; `skip_penalty_seconds` ≥ 0;
  `screen_time_days_per_bucket` ≥ 1; `screen_time_max_days` ≥
  `screen_time_days_per_bucket`; `history_depth` ≥ 1; the quality filter
  passes `filter.Validate`.

**Tests:** missing file → defaults · empty file → defaults · a partial file
overrides only its keys · `interval = 600` (integer) and `interval = 0.5`
both decode · unknown key → error · each validation rule · `~/` expansion.

### Step 6 — Config: first-run template

**Branch** `feature/config-template` · **Commit** `feat(config): write commented default config on first run` · **Spec** §8

- Add `internal/config/default_config.toml`, embedded with `//go:embed`. It
  lists **every** top-level setting as a commented `# key = value` line with
  its default and a short explanation. After them, at the end: a commented
  `# [default_quality_filter]` example, then the commented backend examples
  exactly as in spec §8. Commented, not active, so future default changes
  still reach users who never edited a value.
- `func EnsureFile(path string) (created bool, err error)` writes the
  template if the file doesn't exist and never overwrites.
- `var ErrBackendNotConfigured` — returned later (step 17) by anything that
  needs to set a wallpaper while `WallpaperCommand` is nil. Its message
  names the config file and says to uncomment one of the examples.

**Tests:** `EnsureFile` creates once and doesn't overwrite a modified file ·
the template decodes without error as-is · **sync test**: take the lines
before the first commented table header (`# [`), uncomment those matching
`^# [a-z_]+ =\s`, decode the result, and compare to `Defaults()` — this fails
whenever the template and the defaults drift apart.

### Step 7 — CLI skeleton

**Branch** `feature/cli-skeleton` · **Commit** `refactor(cli): move command dispatch into internal/cli` · **Decisions** D16

Move dispatch out of `main.go` so later steps only add one file each.

```go
// internal/cli/cli.go
type Environment struct {
	Stdout  io.Writer
	Stderr  io.Writer
	Stdin   io.Reader
	Now     func() time.Time
	Version string
}

type Command struct {
	Name    string
	Summary string // one line, shown in help
	Run     func(arguments []string, environment Environment) error
}

// Run dispatches arguments (os.Args[1:]) and returns the exit code:
// 0 success, 1 error, 2 usage error.
func Run(arguments []string, environment Environment) int
```

- A package-level command list; `help` prints every command's name and
  summary from it, so help never gets out of sync.
- Each command parses its own flags with
  `flag.NewFlagSet(name, flag.ContinueOnError)` writing to `Stderr`.
- `version` and `help` move here. `version.go` stays in `main` (the
  Makefile injects `main.injectedVersion`); `main.go` passes the result as
  `Environment.Version`.
- `main.go` shrinks to building the `Environment` and
  `os.Exit(cli.Run(os.Args[1:], environment))`.
- Bare `yarwm` prints help and exits 2 (D16).

**Tests:** unknown command → 2 and an error on stderr · `help` lists every
registered command · `version` prints the given version.

---

## Phase 2 — Library and tags

### Step 8 — Library scan

**Branch** `feature/library-scan` · **Commit** `feat(library): scan library with ignore files` · **Spec** §3 · **Decisions** D21

`internal/library/scan.go`:

```go
// Scan returns the absolute paths of all images under root, sorted.
func Scan(root string, recursive bool) ([]string, error)
```

- Images by extension (D21), case-insensitive.
- In each directory, a `.ignore` file holds one pattern per line (blank
  lines and lines starting with `#` skipped). An entry is skipped when its
  **name** matches any pattern with `filepath.Match`. Patterns apply to
  their own directory only. An invalid pattern is an error naming the
  `.ignore` file and line.
- Don't descend into directories when `recursive` is false. Don't follow
  symlinked directories (loops); a symlinked file is included if it points
  to a regular file.
- A missing `root` is an error wrapping `fs.ErrNotExist`, so the CLI can say
  "library_path ... does not exist".

**Tests** (build a tree in `test.TempDir()`): finds images, skips other
files · extension case · recursive on/off · `.ignore` skips a file and a
whole subdirectory · `.ignore` in a subdirectory doesn't affect its parent ·
invalid pattern → error · missing root → `errors.Is(err, fs.ErrNotExist)`.

### Step 9 — Content hashing and library index

**Branch** `feature/library-index` · **Commit** `feat(library): cache content hashes in a library index` · **Spec** §1 · **Decisions** D8

`internal/library/index.go`:

```go
func HashFile(path string) (string, error) // SHA-256, hex, streamed (io.Copy)

type IndexEntry struct {
	Size            int64  `json:"size"`
	ModTimeUnixNano int64  `json:"mod_time_unix_nano"`
	Hash            string `json:"hash"`
}

type Index map[string]IndexEntry // absolute path → entry

// Refresh updates index for exactly the given paths: entries for paths
// no longer present are dropped, files whose size and mtime are unchanged
// keep their hash, everything else is hashed with hashFile.
// It returns hash → path for the library (when two files have the same
// content, the first path in sorted order wins) and whether the index
// changed.
func Refresh(index Index, paths []string, hashFile func(string) (string, error)) (byHash map[string]string, changed bool, err error)

func LoadIndex(path string) (Index, error)
func (index Index) Save(path string) error
```

**Tests:** `HashFile` of a known string · unchanged file is not rehashed
(count calls on a fake `hashFile`) · modified file is rehashed · moved file
keeps its hash under the new path · removed file disappears · identical
content in two files → one hash, first path wins · `changed` is false when
nothing changed.

### Step 10 — Tags store

**Branch** `feature/tags-store` · **Commit** `feat(tags): add tags store` · **Spec** §1 · **Decisions** D1, D2

`internal/tags/tags.go`:

```go
const (
	MinValue         = 1
	MaxValue         = 10
	DefaultFrequency = 5 // D2
)

type Entry struct {
	Quality   *int   `json:"quality,omitempty"`
	Frequency *int   `json:"frequency,omitempty"`
	CachePath string `json:"cache_path"`
}

type Store map[string]Entry // content hash → entry

func Load(path string) (Store, error)
func (store Store) Save(path string) error

// Set updates whichever of quality/frequency is non-nil, validating 1–10,
// and records cachePath as the last known location.
func (store Store) Set(hash, cachePath string, quality, frequency *int) error

func (store Store) Quality(hash string) (quality int, tagged bool)
func (store Store) Frequency(hash string) int // DefaultFrequency when unset
```

**Tests:** set quality only, frequency stays unset · set both · out-of-range
→ error and no change · `Frequency` default · save → load round-trip
(unset fields stay absent in the JSON).

### Step 11 — `tag <file>`

**Branch** `feature/tag-command` · **Commit** `feat(cli): add tag command for files` · **Spec** §1

`yarwm tag <file> [--quality N] [--frequency N]`

- Resolve `<file>` to an absolute path; it must be an existing regular
  file. Hash it with `library.HashFile`.
- With `--quality` and/or `--frequency`: under the file lock (step 4),
  load tags, `Set`, save, and print the result
  (`tagged /path/x.jpg: quality 7, frequency 5 (default)`).
- With neither flag: print the file's current tags and change nothing.
- Keyword targets (`current`, `last`, `next`) come in step 23.

**Tests** (temp XDG dirs + temp image file): tag sets values in
`tags.json` · second call changes only the given field · no flags prints
without writing · missing file → error · invalid value → exit 1.

**Try it:** `make build`, then on the host
`./build/yarwm tag ~/Pictures/some.jpg --quality 8` and inspect
`~/.config/yarwm/tags.json`.

### Step 12 — `tag-bulk`

**Branch** `feature/tag-bulk` · **Commit** `feat(cli): add tag-bulk command` · **Spec** §1 · **Decisions** D19

```text
yarwm tag-bulk [--pattern GLOB]
               [--filter-quality N | --filter-quality-min N --filter-quality-max N]
               [--filter-frequency N | --filter-frequency-min N --filter-frequency-max N]
               [--set-quality N] [--set-frequency N] [--yes]
```

- At least one `--set-*` is required.
- Candidates: scan the library and refresh the index (steps 8–9) → every
  current wallpaper, tagged or not (D19).
- Put the matching in a pure function in `internal/tags`:
  `Match(candidates map[string]string, store Store, criteria Criteria, libraryRoot string) []string`
  (hashes, sorted by path), with `Criteria{Pattern string; Quality, Frequency filter.Range}`.
- Show the match count and the first 10 paths, then ask
  `Apply to N wallpapers? [y/N]` on stdin unless `--yes`. Zero matches →
  say so, exit 0.
- Apply all changes under one file lock, one save.

**Tests:** `Match` with pattern on file name · pattern with `/` against the
relative path · quality filter excludes untagged · frequency filter uses the
default for untagged · filters combine with AND · CLI: answering `n` changes
nothing; `--yes` applies; missing `--set-*` → usage error.

### Step 13 — Migration tool

**Branch** `feature/migrate` · **Commit** `feat(migrate): import quality from nested quality-N folders` · **Spec** §2

`cmd/migrate/main.go` — its own binary, deleted after use.

```text
migrate [--dry-run] <old-root>
```

- Walk `<old-root>` recursively for images (reuse `library.Scan`).
- A file's quality is `N` from the **deepest** path component matching
  `^quality-([0-9]+)$` (pure function
  `qualityFromRelativePath(relativePath string) (quality int, found bool)`).
  Files with no such component are listed as skipped.
- Hash each file and `Set` its quality only (frequency untouched) under one
  file lock and one save. `--dry-run` prints what it would do and writes
  nothing.
- Print a summary: tagged, skipped, out-of-range quality.

**Tests:** `qualityFromRelativePath`: `quality-1/a.jpg` → 1;
`quality-1/quality-2/quality-3/a.jpg` → 3; `misc/a.jpg` → not found ·
end-to-end on a temp tree, including `--dry-run` writing nothing.

**Try it:** build it in the container
(`docker compose run --rm dev go build -o build/migrate ./cmd/migrate`),
then on the host: `./build/migrate --dry-run ~/Pictures/wallpapers`.

---

## Phase 3 — Choosing a wallpaper

### Step 14 — History and screen-time buckets

**Branch** `feature/history` · **Commit** `feat(history): track screen time in day buckets` · **Spec** §6 · **Decisions** D12

`internal/history/history.go`:

```go
type Entry struct {
	LastShown         *float64           `json:"last_shown"`          // Unix seconds; null = never
	ScreenTimeBuckets map[string]float64 `json:"screen_time_buckets"` // bucket start date → seconds
}

type Store map[string]Entry

func Load(path string) (Store, error)
func (store Store) Save(path string) error

// BucketKey is the UTC start date of the bucket containing moment (D12).
func BucketKey(moment time.Time, daysPerBucket int) string

func (store Store) SetLastShown(hash string, now time.Time)

// CloseOut adds now − LastShown (plus extraSeconds, used by skip) to the
// bucket containing LastShown, then prunes buckets that started more than
// maxDays ago. Does nothing if the wallpaper was never shown. A negative
// duration (clock moved back) counts as 0.
func (store Store) CloseOut(hash string, now time.Time, extraSeconds float64, daysPerBucket, maxDays int)

// ScreenTime sums the buckets that started within maxDays of now.
func (store Store) ScreenTime(hash string, now time.Time, maxDays int) float64
```

Floating-point Unix seconds keep sub-second intervals meaningful.

**Tests** (fixed `time.Date(...)` values): `BucketKey` with 1-day and
7-day buckets, around midnight UTC · `CloseOut` adds the duration to the
start's bucket · `extraSeconds` is added · pruning drops old buckets ·
`ScreenTime` ignores out-of-window buckets even if they weren't pruned ·
never-shown → `CloseOut` is a no-op · mixed bucket sizes (after a config
change) still sum correctly.

### Step 15 — Scoring

**Branch** `feature/scoring` · **Commit** `feat(selection): add scoring formula` · **Spec** §6 step 4 · **Decisions** D6

`internal/selection/score.go`:

```go
func FrequencyWeight(frequency int, baseF float64) float64 // baseF^frequency

// AgeFactor is seconds since lastShown, at least 1. Never shown (nil)
// counts as neverShownAgeSeconds (D6: screen_time_max_days in seconds).
func AgeFactor(lastShown *float64, now time.Time, neverShownAgeSeconds float64) float64

func FreshnessFactor(screenTimeSeconds, decayF, decayScaleSeconds float64) float64 // decayF^(screenTime/decayScale)

func Score(frequency int, lastShown *float64, screenTimeSeconds float64, now time.Time, settings ScoreSettings) float64

type ScoreSettings struct {
	BaseF, DecayF, DecayScaleSeconds, NeverShownAgeSeconds float64
}
```

The floor of 1 second on age keeps every score above zero, so nothing is
ever excluded outright (spec §6 step 5).

**Tests:** `FrequencyWeight(10, 2) == 1024` · higher frequency → higher
score, all else equal · older → higher · more screen time → lower ·
`FreshnessFactor(0, ...) == 1` · never-shown uses the configured age ·
every score > 0.

### Step 16 — Candidate pool and weighted pick

**Branch** `feature/weighted-pick` · **Commit** `feat(selection): pick from the pool by weighted random draw` · **Spec** §6 steps 3 and 5 · **Decisions** D2, D3, D7

`internal/selection/pick.go`:

```go
type Candidate struct {
	Hash  string
	Path  string
	Score float64
}

// BuildPool applies the quality filter (D3), drops excludeHash unless it
// is the only candidate (D7), and scores the rest. Sorted by path.
func BuildPool(library map[string]string, tagStore tags.Store, historyStore history.Store,
	qualityFilter filter.Range, excludeHash string, now time.Time,
	maxDays int, settings ScoreSettings) []Candidate

// Pick draws one candidate with probability proportional to its score.
func Pick(candidates []Candidate, random *rand.Rand) (Candidate, error)

var ErrEmptyPool = errors.New("no wallpapers match")
```

`Pick`: sum the scores, draw `random.Float64() * total`, walk the
cumulative sum until it passes the draw.

**Tests:** empty pool → `ErrEmptyPool` · single candidate always picked ·
statistical check with a fixed seed: over 10 000 draws, a score-3
candidate is picked about 3× as often as a score-1 one (assert within
±10%) · `BuildPool`: filter excludes untagged, no filter includes them,
current excluded, current kept when it's the only one.

### Step 17 — Wallpaper backend

**Branch** `feature/backend` · **Commit** `feat(backend): run the configured wallpaper command` · **Spec** §4 · **Decisions** D17

`internal/backend/backend.go`:

```go
type Displayer interface {
	Show(ctx context.Context, imagePath string) error
}

// New returns config.ErrBackendNotConfigured when command is nil or empty.
func New(command *config.BackendCommand) (Displayer, error)
```

- Replace `{path}` inside every argument (`strings.ReplaceAll`, so
  `",{path}"` for hyprpaper works). Run with `exec.CommandContext`, no
  shell, 30-second timeout.
- A non-zero exit returns an error with the exit code and trimmed stderr.

**Tests** (real processes, no backend needed):

- a command that records its argument: program `sh`, arguments
  `["-c", "printf '%s' \"$1\" > \"$OUT\"", "sh", "{path}"]`, with `OUT`
  set by `test.Setenv` to a temp file → the file contains the image path
- missing program → error · `false` → error with its exit code
- `sleep 5` with a short context deadline → error
- nil command → `config.ErrBackendNotConfigured`

### Step 18 — Session filter

**Branch** `feature/session-filter` · **Commit** `feat(selection): remember the last explicit quality filter` · **Spec** §7 (quality filter fallback chain) · **Decisions** D18

`internal/selection/sessionfilter.go`:

```go
// ResolveFilter returns the active quality filter:
//  1. explicit (given on this command) — saved to the session filter file,
//  2. else the saved session filter, if the file exists,
//  3. else configDefault.
func ResolveFilter(explicit *filter.Range, configDefault filter.Range, sessionFilterPath string) (filter.Range, error)
```

And in `internal/cli`, a flag helper every generating command reuses:

```go
// AddQualityFlags registers --quality, --quality-min and --quality-max.
// The returned function gives nil when none was passed.
func AddQualityFlags(flagSet *flag.FlagSet) func() (*filter.Range, error)
```

**Tests:** explicit wins and is saved · no explicit → saved one · nothing
saved → config default · flag helper: none → nil; `--quality-min 7` →
min 7; `--quality 5 --quality-min 3` → error.

---

## Phase 4 — Rotation

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

Callers pass `tags.json` and `library_index.json`. History is _not_ passed:
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

Steps, all under the file lock:

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
  `EnsureNext(ctx, dependencies) (NextPick, error)` — under the file lock,
  it recomputes and **saves** (D15); step 30 reuses it.
- A literal file named `current` is reachable as `./current`.

**Tests:** each keyword resolves to the right hash · no target = current ·
empty state → error · stale `next` is recomputed and saved.

---

## Phase 5 — Daemon

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

- Add a cache to `internal/jsonfile`:
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

---

## Phase 6 — Browsing and extras

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

```text
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
file lock; if anything splits, ask `[y/N]` unless `--yes`.

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
- Fold the confirmed [decisions](#decisions) into `spec.md`.

**Release v0.2.0** after this step.
