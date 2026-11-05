# Phase 3 — Choosing a wallpaper

The pieces of a pick: screen-time history, scoring, the weighted draw, the wallpaper backend and the session filter.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

## Step 14 — History and screen-time buckets

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

## Step 15 — Scoring

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

## Step 16 — Candidate pool and weighted pick

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

## Step 17 — Wallpaper backend

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

## Step 18 — Session filter

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
