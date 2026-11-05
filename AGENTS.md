# AGENTS.md

Instructions for coding agents working on yarwm, a wallpaper rotation
daemon and CLI in Go. Humans: the same rules live in `README.md` and
`CONTRIBUTING.md`; this file points to them.

## Before you change anything

- Read `docs/spec.md` (the design) and `CONTRIBUTING.md` (workflow and
  code style).
- Implementation work follows `docs/plan/`. Only implement steps from a
  phase file that is merged into `dev`. **Never implement from
  `docs/plan/DRAFT-full-plan.md`**: it is unreviewed.
- If the spec, the plan and the code disagree, stop and ask instead of
  picking one.

## Commands

Go is not installed on the host. Everything runs in the dev container
through `make`; never call `go` directly.

```sh
make check   # fmt-check, lint, test: what CI runs, must pass before a PR
make test
make fmt
make build   # build/yarwm
make run ARGS="version"
```

## Code

- Packages go under `internal/`; `main.go` only dispatches.
- Pass time, randomness and the wallpaper backend in as parameters
  (dependency injection) so tests can control them.
- Tests use `test.TempDir()` and `test.Setenv` for every XDG directory, and
  never touch real user files.
- **Comments:** follow "Code style" in `CONTRIBUTING.md`. In short: no
  comments that restate the code; only "why" comments and Go doc comments.
  Comments inside the plan's code snippets are spec, not code to copy.
- Don't add dependencies the spec or plan doesn't call for.
- Don't bump versions by hand (Dockerfile `FROM` lines, existing `go.mod`
  requires): Dependabot owns them. Adding a dependency the plan calls for
  is fine.

## Git

- Gitflow: branch `feature/<name>` from `dev`, never from another feature
  branch. Open a pull request into `dev`. Never commit to `dev` or `main`
  directly.
- **Never force push, to any branch.** Don't rebase or amend commits that
  are already pushed; to bring in new `dev` changes, merge `dev` into your
  branch.
- Commits follow Conventional Commits with the types listed in
  `CONTRIBUTING.md`.
- **Push your branch and open the pull request, but don't merge it.** The
  maintainer merges.
