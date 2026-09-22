# docs/vendor — Helix Steel documentation and modules

Frozen copy (vendored) of the Helix Steel documentation and the Scheme
modules of the helix-term Steel engine, extracted from a Helix source
checkout.

## Provenance

- **Source** : a Helix repository checkout
- **Branch** : `steel-event-system`
- **Commit** : `09d67dfe7300ab18c267e6b0cbfbb493cce21d37` ("update steel")
- **Date** : Thu Sep 17 07:35:21 2026 -0700

## Contents

- `STEEL.md` — guide for writing Helix Steel plugins
- `steel-docs.md` — reference generated from that very commit
  (contents of the Rust BuiltInModules + Scheme modules)
- `helix/*.scm` — the 10 Scheme modules exposed by the engine:
  `commands`, `static`, `editor`, `misc`, `treesitter`, `ext`,
  `keymaps`, `configuration`, `themes`, `components`

## Caveats

- The **binary actually in use** at vendoring time was `hx 25.07.1`
  (commit `8d189f46`). The real binary may differ from this copy;
  when in doubt about a signature, test against the real binary.
- This commit's `steel-docs.md` **does not list** some functions that
  are actually exposed (e.g. `query-document`, `string->tsquery`,
  `tsquery-loader`, `editor-count` — verified by grep on 2026-09-22).
  When `steel-docs.md` and a vendored `.scm` disagree, **trust the
  `.scm`**: the module code defines the `provide`s.
- Rust builtin modules (`helix/core/text`, `helix/core/misc`, …) are
  not `.scm` files: the only references are `steel-docs.md` and the
  Rust source (helix-core/src/extensions.rs).

## Regeneration

Set `HELIX_SRC` to a Helix repository checkout:

```bash
HELIX_SRC=${HELIX_SRC:?set HELIX_SRC to a Helix checkout}
cp "$HELIX_SRC/STEEL.md" "$HELIX_SRC/steel-docs.md" docs/vendor/
for m in commands static editor misc treesitter ext keymaps configuration themes components; do
  cp "$HELIX_SRC/helix-term/src/commands/engine/steel/$m.scm" docs/vendor/helix/
done
./scripts/gen-api-index.sh
```
