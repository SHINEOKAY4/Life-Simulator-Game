# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added

- GitHub issue templates for bug reports and feature requests.
- CI workflow with:
  - Lua test execution (`busted`)
  - Rojo build artifact publishing
  - Docusaurus docs build and GitHub Pages deployment on `main`
- Initial Lua test harness:
  - `run_tests.sh`
  - `Tests/Specs/ExampleSpec.lua`
  - `Tests/Specs/PlotSpec.lua`
  - `Tests/Specs/TenantSpec.lua`
- Dynamic documentation scaffold under `docs/` with generated architecture/API pages.

### Changed

- `.gitignore` now excludes Docusaurus build/dependency outputs in `docs/`.
- Docs generation script hardened to emit MDX-safe API docs.
