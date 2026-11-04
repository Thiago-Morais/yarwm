# Implementation plan

This breaks [`spec.md`](../spec.md) into small steps. Each step is one
feature branch and one pull request, small enough to finish in a sitting,
and ends with a green `make check`. Steps are ordered so every one builds
only on what came before.

## Phases

The plan is split into one file per phase. **Each phase file is added to
`dev` by its own pull request, and merging it is the review.** So the rule
is simple: if a phase's file isn't in this directory yet, it hasn't been
reviewed — don't start its steps.

| Phase | File | Steps | Result |
|---|---|---|---|
| 1. Foundations | `phase-1-foundations.md` | 1–7 | Filter type, paths, JSON files, state lock, config, CLI skeleton |
| 2. Library and tags | `phase-2-library-and-tags.md` | 8–13 | **Milestone:** tag wallpapers (`tag`, `tag-bulk`) and migrate the old `quality-N` folders |
| 3. Choosing a wallpaper | `phase-3-choosing-a-wallpaper.md` | 14–18 | History, scoring, weighted pick, backend, session filter |
| 4. Rotation | `phase-4-rotation.md` | 19–23 | **Milestone:** `next` / `skip` change the wallpaper by hand |
| 5. Daemon | `phase-5-daemon.md` | 24–27 | **Milestone:** automatic rotation → **release v0.1.0** |
| 6. Browsing and extras | `phase-6-browsing-and-extras.md` | 28–33 | `previous`/`undo`/`redo`/`clamp`, `status`, `rebucket`, docs → **release v0.2.0** |

### Draft of the full plan

[`DRAFT-full-plan.md`](DRAFT-full-plan.md) holds the whole plan, unreviewed,
so the overall structure is visible while phases are reviewed one at a
time. **Never implement from it** — only from reviewed phase files. Delete
it as soon as possible, at the latest in the pull request that adds the
last phase file.

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
- **Testable by construction.** Anything time-, randomness- or
  process-dependent takes it as a parameter: the current time
  (`now time.Time` or `now func() time.Time`), the random source
  (`*rand.Rand` from `math/rand/v2`, seeded in tests with
  `rand.New(rand.NewPCG(1, 2))`), and the wallpaper backend (an interface,
  faked in tests).
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
the step that depends on it is listed (steps live in the phase files). Change any of them before that step
starts, and fold them into `spec.md` once settled.

| # | Topic | Decision | Used in |
|---|---|---|---|
| D1 | Tag values | `quality` and `frequency` are integers 1–10; anything else is rejected | 10 |
| D2 | Untagged frequency | A wallpaper with no `frequency` counts as **5** (the middle) | 10, 16 |
| D3 | Untagged quality | Eligible when no quality filter is active; excluded by any active filter (spec §8) | 16 |
| D4 | `base_f` default | **2** — each frequency point doubles the odds | 5 |
| D5 | `skip_penalty_seconds` default | **1800** (three default intervals) | 5 |
| D6 | Never-shown age | A wallpaper never shown counts as last shown `screen_time_max_days` ago (30 days by default): a strong but finite boost | 15 |
| D7 | Repeats | The wallpaper on screen is excluded from the pool, unless it's the only candidate | 16 |
| D8 | Library rescans | The library (directory listing + `stat`) is rescanned before every pick. Content hashes are cached in a **`library_index.json`** state file (path → size, mtime, hash), so only new or changed files are hashed | 9, 21 |
| D9 | Concurrent writes | The daemon and CLI commands are separate processes writing the same files. Every state change holds an exclusive lock on a `lock` file in the state directory (`flock`) for its whole read-modify-write | 4, 11+ |
| D10 | Corrupt state files | A JSON file that fails to parse is an **error**, never silently replaced (replacing it would wipe the data) | 3 |
| D11 | Midnight | Tick alignment counts from **local** midnight | 24 |
| D12 | Buckets | Keys are UTC dates (`2006-01-02`); bucket starts are aligned to the Unix epoch in `screen_time_days_per_bucket` steps. A show's whole duration goes to the bucket containing its start. A bucket counts toward screen time — and survives pruning — while its **start** is within `screen_time_max_days` of now. Screen time filters by the window when reading, since pruning only happens on close-out | 14 |
| D13 | Daemon start | `yarwm start` re-displays `recent[0]` right away if there is one (the screen is usually blank after login) without counting it as a rotation; otherwise it does a real rotation. Then it waits for the next aligned tick | 26 |
| D14 | Single daemon | A second `yarwm start` refuses to run while one is already running (non-blocking lock on `daemon.lock`) | 26 |
| D15 | `query_next_image` when stale | Recomputes the pick and **saves** it, so the printed path is what the next rotation shows | 23, 30 |
| D16 | Bare `yarwm` | Prints help, as now; the daemon is `yarwm start` | 7 |
| D17 | Backend calls | No shell; `{path}` is replaced inside every argument; wait for exit with a 30-second timeout; a non-zero exit is an error carrying stderr | 17 |
| D18 | Quality filter flags | `--quality N`, `--quality-min N`, `--quality-max N` on `next`, `redo`, `skip` and `start`. In the config: a `[default_quality_filter]` table with `exact`, `min`, `max` | 1, 18 |
| D19 | `tag-bulk` scope and pattern | Candidates are all wallpapers currently in the library, tagged or not. `--pattern` without `/` matches the file name; with `/`, the path relative to `library_path`. An unset quality never matches a quality filter; frequency filters use the effective frequency (D2) | 12 |
| D20 | `rebucket` | `yarwm rebucket` only reports what would change; `yarwm rebucket --force` applies it, asking for confirmation when buckets would be split (`--yes` skips the prompt) | 32 |
| D21 | Image types | `.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`, `.bmp` (case-insensitive) | 8 |
| D22 | Monitors | One wallpaper shared by all monitors (spec §11 default) | — |
