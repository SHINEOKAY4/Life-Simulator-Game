# TODO - Life-Simulator-Game

Last updated: 2026-02-14

## Completed Infrastructure

- [x] Add GitHub issue templates
  - `.github/ISSUE_TEMPLATE/bug-report.yml`
  - `.github/ISSUE_TEMPLATE/feature-request.yml`
  - `.github/ISSUE_TEMPLATE/config.yml`
- [x] Add CI workflow for tests, Rojo build, and docs build/deploy
  - `.github/workflows/build.yml`
- [x] Add Lua test runner and initial spec suite
  - `run_tests.sh`
  - `Tests/Specs/ExampleSpec.lua`
  - `Tests/Specs/PlotSpec.lua`
  - `Tests/Specs/TenantSpec.lua`
- [x] Scaffold dynamic docs site and source-driven generation
  - `docs/` (Docusaurus + `docs/scripts/generate-docs.mjs`)
- [x] Add initial changelog scaffold
  - `CHANGELOG.md`

## Verified Locally

- [x] `./run_tests.sh` passes
- [x] `busted Tests/Specs/*.lua` passes
- [x] `npm run build --prefix docs` passes

## Next Work (Product/Code Depth)

- [ ] Replace stub-heavy tests with behavior tests against production service logic
  - Focus first on `PlotService` and `TenantService` edge cases
- [ ] Add CI lint step for Luau source (`selene`)
- [ ] Expand public docs with gameplay/system overviews and contributor setup guidance
- [ ] Enable release process that updates `CHANGELOG.md` from merged PR metadata
