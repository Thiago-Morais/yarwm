# Contributing

## Branch model (gitflow)

| Branch | Branches off | Merges into | Purpose |
|---|---|---|---|
| `main` | — | — | Released versions only. Every commit on `main` is a tagged release. |
| `dev` | `main` | — | Integration branch. Always builds and passes `make check`. |
| `feature/<name>` | `dev` | `dev` | One feature or change. |
| `release/<version>` | `dev` | `main`, then `main` back into `dev` | Stabilizing a release: fixes and docs only, no new features. |
| `hotfix/<version>` | `main` | `main`, then `main` back into `dev` | Urgent fix to a released version. |

Everything reaches `main` and `dev` through a pull request — GitHub
rejects direct pushes (see [Repository rules](#repository-rules)).

## Merge strategy

| Into | Allowed | Use |
|---|---|---|
| `dev` | Squash, Rebase, Merge | **Squash** by default |
| `main` | Merge only | — |

**Features are squashed by default.** Commit as often and as messily as
you like on a feature branch; it lands on `dev` as one clean commit. Each
feature should be small enough to describe in a single commit message —
if it isn't, split it into two features.

**Rebase** when a branch holds several meaningful commits you want to keep
individually: tidy them first (`git rebase -i --autosquash dev`, then
`git push --force-with-lease`), and they land on `dev` one by one in a
straight line. **Merge** keeps the branch's commits under a merge commit;
use it for back-merges from `main`.

**Into `main`, only real merge commits — never squash or rebase.** Both
rewrite commits, so `main` would hold copies of `dev`'s commits instead of
the commits themselves; git would no longer see the shared history, and
the next merge between `main` and `dev` would turn into conflicts.

### Feature

```sh
git switch dev && git pull
git switch -c feature/<short-name>
# ...work, commit...
git push -u origin feature/<short-name>
```

Open a pull request into `dev` (GitHub offers a **Compare & pull request**
button after the push). CI runs `make check` on it; merging is blocked
until it's green. If `dev` moved in the meantime, bring it in with
`git merge dev` (or `git rebase dev` + `git push --force-with-lease`).

Merge with **Squash and merge**, using a conventional commit message as
the title (see [Commit messages](#commit-messages)). Then delete the
branch on GitHub and locally:

```sh
git switch dev && git pull
git branch -D feature/<short-name>   # -D: git can't tell a squash was merged
```

### Release

```sh
git switch dev && git pull
git switch -c release/<version>       # e.g. release/0.1.0
# final fixes and docs only — the tag below is the version, nothing to bump
git push -u origin release/<version>
```

1. Pull request `release/<version>` → `main`, **Create a merge commit**.
2. Tag the merge on `main`:

   ```sh
   git switch main && git pull
   git tag -a v<version> -m "v<version>"
   git push origin v<version>
   ```

3. Pull request `main` → `dev`, **Create a merge commit**, so `dev`
   contains the release merge and any fixes made on the release branch.
4. Delete `release/<version>`.

### Hotfix

Same as a release, but branch from `main` as `hotfix/<version>` (the
current version with the patch number + 1).

## Repository rules

Configured on GitHub under **Settings → Rules → Rulesets** (not stored in
the repo):

| Ruleset | Type | Target | Rules |
|---|---|---|---|
| dev | branch | `dev` | Restrict deletions; require a pull request (0 approvals; Squash, Rebase, Merge allowed); require status check `check`; block force pushes |
| main | branch | `main` | Same, but only Merge allowed |
| releases | tag | `v*` | Restrict deletions; block force pushes — a published version never moves |

The repository admin may bypass the branch rulesets **for pull requests
only** — e.g. to merge with a red CI in an emergency — but can't push
directly either.

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

On a feature branch this is encouraged but not enforced. **Everything
that lands on `dev` must follow it:** when squashing, the pull request
title (GitHub uses it as the commit title); when rebasing, every commit.

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

## Code style

**Names** are descriptive; single letters only where Go convention makes
them obvious. Accessors have no `Get` prefix (`ScreenTime()`, not
`GetScreenTime()`).

**Comments** are a last resort: if code needs one to be understood, first
try better names, a smaller function, or a test that shows the behaviour.
What stays:

- **Why, not what.** A comment for a reason the code can't express: an
  outside constraint, a workaround, a non-obvious consequence of changing
  it. Never one that restates what the next lines do.
- **Go doc comments** where Go convention expects them: the package
  comment and exported names ([Go Doc Comments](https://go.dev/doc/comment)).
  Keep them to what the name and signature don't already say.
- Nothing commented out, no `TODO`s — open an issue instead.

The same applies to the Makefile, Dockerfile and other config files.

## Before merging into `dev`

- `make check` passes locally — CI runs it too, and blocks the merge if
  it fails.
- Follow the code style above, comments included.
- The commits landing on `dev` follow the commit convention above.
