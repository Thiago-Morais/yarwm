# Phase 1 — Foundations

Building blocks every later step uses: the filter type, file paths, JSON state files, the file lock, config loading, and the CLI skeleton. Nothing user-facing yet.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

## Step 1 — Quality filter type

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

## Step 2 — XDG paths

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

## Step 3 — JSON state files

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

## Step 4 — File lock

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

## Step 5 — Config: defaults and loading

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

## Step 6 — Config: first-run template

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

## Step 7 — CLI skeleton

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
