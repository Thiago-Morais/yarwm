# Contributing

## Branch model (gitflow)

| Branch | Branches off | Merges into | How | Purpose |
|---|---|---|---|---|
| `main` | — | — | — | Released versions only. Every commit on `main` is a tagged release. |
| `dev` | `main` | — | — | Integration branch. Always builds and passes `make check`. |
| `feature/<name>` | `dev` | `dev` | squash | One feature or change. |
| `release/<version>` | `dev` | `main` **and** `dev` | `--no-ff` merge | Stabilizing a release: fixes and docs only, no new features. |
| `hotfix/<version>` | `main` | `main` **and** `dev` | `--no-ff` merge | Urgent fix to a released version. |

Never commit directly to `main` or `dev`.

## Merge strategy

**Features are squash-merged into `dev`.** Commit as often and as messily
as you like on a feature branch; it lands on `dev` as one clean commit.
Each feature should be small enough to describe in a single commit message
— if it isn't, split it into two features.

If a feature branch genuinely holds several independent, meaningful
commits, tidy them with `git rebase -i --autosquash dev` and merge without
squashing instead. That is the exception, not the default.

**Releases and hotfixes are real merges (`--no-ff`), never squashed.**
Squashing `dev` into `main` would make git forget that `main` contains
those commits, and the next merge between `main` and `dev` would turn into
conflicts. Gitflow relies on the two sharing history.

### Feature

```sh
git switch dev && git pull
git switch -c feature/<short-name>
# ...work, commit, push the branch for review...
git push -u origin feature/<short-name>

# once approved:
git merge dev                        # or rebase onto dev, if dev has moved
make check
git switch dev && git pull
git merge --squash feature/<short-name>
git commit                           # write the conventional commit message
git push origin dev
git branch -D feature/<short-name>   # -D: git can't tell a squash was merged
git push origin --delete feature/<short-name>
```

### Release

```sh
git switch dev && git pull
git switch -c release/<version>       # e.g. release/0.1.0
# final fixes and docs only — the tag below is the version, nothing to bump
make check
git switch main && git merge --no-ff release/<version>
git tag -a v<version> -m "v<version>"
git switch dev  && git merge --no-ff release/<version>
git push origin main dev --tags
git branch -d release/<version>
```

### Hotfix

Same as a release, but branch from `main` as `hotfix/<version>` (the
current version with the patch number + 1) and merge back into both
`main` and `dev`.

## Commit messages

[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>(<optional scope>): <description>

<optional body: why, not what>
```

| Type | For |
|---|---|
| `feat` | a new user-facing capability |
| `fix` | a bug fix |
| `refactor` | code change with no behavior change |
| `test` | adding or fixing tests only |
| `docs` | documentation only |
| `build` | dev container, Makefile, `go.mod`, dependencies |
| `ci` | GitHub Actions workflows |
| `chore` | anything else that doesn't touch the program (e.g. `.gitignore`) |

- Scope is the package or area, e.g. `feat(history): bucket screen time by day`.
- Description: imperative, lower case, no trailing period — "add", not
  "added" or "adds".
- Breaking change: `!` after the type/scope (`feat(config)!: ...`) plus a
  `BREAKING CHANGE:` line in the body.

On a feature branch this is encouraged but not enforced. **The squash
commit on `dev` must follow it.**

## Versioning

[Semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`, tags are
`v`-prefixed (`v0.1.0`). While pre-1.0, minor bumps may break things.

The git tag **is** the version — nothing in the source is bumped by hand.
`make build` runs `git describe --tags --always --dirty` on the host and
injects the result, so `yarwm version` prints e.g. `v0.1.0` on a tag,
`v0.1.0-3-g257be6f` three commits later, or `...-dirty` with uncommitted
changes. `go install github.com/Thiago-Morais/yarwm@v0.1.0` gets its version
from the module system instead, without git.

## Tool versions

Nothing is bumped by hand. [Dependabot](.github/dependabot.yml) checks
weekly and opens a pull request against `dev` for each new release of:

| Tool | Pinned in |
|---|---|
| Go toolchain | `docker/dev/Dockerfile` — `FROM golang:<version>-trixie` |
| golangci-lint | `docker/dev/Dockerfile` — `FROM golangci/golangci-lint:<version>` |
| GitHub Actions | `.github/workflows/check.yml` |
| Delve (`go tool dlv`) | `go.mod` — the `tool` line and its `require` |
| Go module dependencies | `go.mod` |

CI runs `make check` on every Dependabot PR; if it's green, review and
merge it like any feature (squash). The dev image rebuilds itself on the
next `make` run.

If a Go bump turns CI red, the usual cause is golangci-lint lagging behind:
it must be built with a Go at least as new as ours (`golangci-lint version`
prints which). Wait for, or merge, the matching golangci-lint PR first.

**The `go` line in `go.mod` is not a toolchain pin.** It's the minimum
Go version the code needs, and stays put when the toolchain is updated.
Raise it only on purpose, when the code starts using a newer language or
standard library feature.

## Before merging into `dev`

- `make check` passes (gofmt, golangci-lint, tests) — CI runs it too.
- Follow the code style in `docs/spec.md`: descriptive names by default,
  single letters only in tiny scopes like one-line functions and simple
  math, no `Get` prefix on accessors. This is a review guideline, not a
  lint rule.
- The squash commit message follows the commit convention above.
