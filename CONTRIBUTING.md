# Contributing

## Branch model (gitflow)

| Branch | Branches off | Merges into | Purpose |
|---|---|---|---|
| `main` | — | — | Released versions only. Every commit on `main` is a tagged release. |
| `dev` | `main` | — | Integration branch. Always builds and passes `make check`. |
| `feature/<name>` | `dev` | `dev` | One feature or change. |
| `release/<version>` | `dev` | `main` **and** `dev` | Stabilizing a release: version bump, fixes, docs. No new features. |
| `hotfix/<version>` | `main` | `main` **and** `dev` | Urgent fix to a released version. |

Never commit directly to `main` or `dev`.

### Feature

```sh
git switch dev && git pull
git switch -c feature/<short-name>
# ...work, commit...
make check
git switch dev && git pull
git merge --no-ff feature/<short-name>
git push origin dev
git branch -d feature/<short-name>
```

Keep feature branches small — one step of the feature plan each — and
rebase onto `dev` (or merge `dev` in) if `dev` has moved before merging.

### Release

```sh
git switch dev && git pull
git switch -c release/<version>       # e.g. release/0.1.0
# bump the version constant in main.go, final fixes only
make check
git switch main && git merge --no-ff release/<version>
git tag -a v<version> -m "v<version>"
git switch dev  && git merge --no-ff release/<version>
git push origin main dev --tags
git branch -d release/<version>
```

### Hotfix

Same as a release, but branch from `main` as `hotfix/<version>` (bumping
the patch number) and merge back into both `main` and `dev`.

## Versioning

[Semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`, tags are
`v`-prefixed (`v0.1.0`). While pre-1.0, minor bumps may break things.

## Before merging into `dev`

- `make check` passes (gofmt, `go vet`, tests).
- Follow the code style in `docs/spec.md`: descriptive names, no
  single-letter variables (loop variables and receivers included), no
  `Get` prefix on accessors.
- Merge with `--no-ff` so every feature stays visible as one unit in the
  history.
