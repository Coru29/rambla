# Contributing to Rambla

Thanks for helping! Issues and pull requests are welcome in English or Spanish.

## Build and test

Only the Xcode Command Line Tools (Swift 6) are needed.

```sh
scripts/test.sh          # unit tests (RamblaCore, Swift Testing)
scripts/install.sh       # build, install to /Applications and launch
scripts/e2e.sh           # live checks with a throwaway test app (needs the Accessibility permission)
```

`swift test` does not run Swift Testing when only the Command Line Tools are installed, so use `scripts/test.sh`.

## Commit messages: Conventional Commits

Versions are computed from commit messages, so every commit follows [Conventional Commits](https://www.conventionalcommits.org):

```
type(optional scope): summary in imperative mood
```

| Type | Use it for | Effect on the next version |
|---|---|---|
| `feat` | a new feature | minor: 1.2.0 → 1.3.0 |
| `fix` | a bug fix | patch: 1.2.0 → 1.2.1 |
| `perf` | a performance improvement | patch |
| `refactor`, `docs`, `style`, `test`, `build`, `ci`, `chore` | everything else | no release by itself |
| `type!:` or a `BREAKING CHANGE:` footer | an incompatible change | major: 1.2.0 → 2.0.0 |

Examples: `fix: keep focus when switching desktops`, `feat(trackpad): three-finger swipe`, `docs: translate the manual`.

Run this once after cloning to have git reject messages that don't follow the format:

```sh
git config core.hooksPath scripts/hooks
```

## Releases (maintainers)

```sh
scripts/release.sh --dry-run   # shows the next version and its release notes
scripts/release.sh             # tests, bumps VERSION, signed DMG, tag vX.Y.Z, GitHub release
```

The release notes are generated from the `feat`, `fix` and `perf` commits since the last tag. Installed copies find the new release within a day and update themselves after verifying the signature.

Every release must be signed with the project's certificate in `.signing/` (created by the first build and never committed): installed copies only accept updates signed with the same certificate. Keep a private backup of that folder.

## Code

- Swift 6 toolchain, language mode 5, no third-party dependencies.
- Pure logic goes in `Sources/RamblaCore` with tests; AppKit code in `Sources/Rambla`.
- Rambla must stay at 0 % CPU when idle: react to events, don't poll.
