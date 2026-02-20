# Life Simulator Docs

Dynamic documentation site powered by Docusaurus and generated from Luau source files.

## Commands

- `npm ci`
- `npm run generate`
- `npm run start`
- `npm run build`

## Generation pipeline

- Scans `src/**/*.luau`
- Parses files with `tree-sitter-luau` (AST validity checks)
- Extracts:
  - exported Luau types (`export type ...`)
  - module public APIs (`function Module.Method(...)` and `function Module:Method(...)`)
  - architecture + feature-area inventories
- Emits Markdown into `docs/content/generated/`
