# Phase 2 — Library and tags

**Milestone:** tag wallpapers with `tag` and `tag-bulk`, and migrate the old `quality-N` folders.

Read the [plan README](README.md) first — it explains how to work
through a step, the conventions, and the decisions referenced below
(D1, D2, …). Spec sections (§) refer to [`spec.md`](../spec.md).

## Step 8 — Library scan

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

## Step 9 — Content hashing and library index

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

## Step 10 — Tags store

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

## Step 11 — `tag <file>`

**Branch** `feature/tag-command` · **Commit** `feat(cli): add tag command for files` · **Spec** §1

`yarwm tag <file> [--quality N] [--frequency N]`

- Resolve `<file>` to an absolute path; it must be an existing regular
  file. Hash it with `library.HashFile`.
- With `--quality` and/or `--frequency`: under the state lock (step 4),
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

## Step 12 — `tag-bulk`

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
- Apply all changes under one state lock, one save.

**Tests:** `Match` with pattern on file name · pattern with `/` against the
relative path · quality filter excludes untagged · frequency filter uses the
default for untagged · filters combine with AND · CLI: answering `n` changes
nothing; `--yes` applies; missing `--set-*` → usage error.

## Step 13 — Migration tool

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
  state lock and one save. `--dry-run` prints what it would do and writes
  nothing.
- Print a summary: tagged, skipped, out-of-range quality.

**Tests:** `qualityFromRelativePath`: `quality-1/a.jpg` → 1;
`quality-1/quality-2/quality-3/a.jpg` → 3; `misc/a.jpg` → not found ·
end-to-end on a temp tree, including `--dry-run` writing nothing.

**Try it:** build it in the container
(`docker compose run --rm dev go build -o build/migrate ./cmd/migrate`),
then on the host: `./build/migrate --dry-run ~/Pictures/wallpapers`.
