# todo.hx

A plugin for [Helix](https://helix-editor.com/) that adds navigation commands to jump between info-level comment tags (TODO, NOTE, PERF, etc.) in your code.

## Features

- **`:todo-next`** — jump to the next info-level comment tag in the current buffer
- **`:todo-prev`** — jump to the previous info-level comment tag in the current buffer

The plugin reuses Helix's own `comment/highlights.scm` tree-sitter query (the `@info` capture) to identify TODO-class markers. This means it shares a single source of truth with Helix's highlighter — if Helix updates the list of recognized tags, navigation follows automatically.

### Recognized tags

All tags captured by `@info` in Helix's `comment/highlights.scm`:

```
INFO  NOTE  TODO  TO-DO  PERF  OPTIMIZE  PERFORMANCE  QUESTION  ASK  REVIEW  PR  CR
```

### Behavior

Mirrors Helix's built-in `goto_next_comment` / `goto_prev_comment` (`]c` / `[c`):

- Strict comparison: the cursor jumps to a tag on a *different* line, never staying on the current line
- No wrap-around: at the last/first tag, the cursor stays put silently
- No status message on no-match (silent no-op)
- Cursor lands on the first non-whitespace character of the target line
- No side effects on editor registers, search state, or selections — the only change is the cursor position

### Limitations

- Requires a tree-sitter parser for the current buffer AND the "comment" language injection to be configured (Helix does this by default for most languages — Rust, Python, JavaScript, CSS, and many others via their `injections.scm` files)
- Buffers without a parser silently no-op (no error, no message)
- Only the current buffer is navigated (no cross-buffer/project-wide navigation in v1)

## Installation

Install the package with [forge](https://github.com/mystborn/forge) (the Steel package manager):

```
forge install todo.hx
```

Then add to your `~/.config/helix/helix.scm`:

```scheme
(require "todo.hx")
(provide (all-from-out "todo.hx"))
```

This makes `todo-next` and `todo-prev` available as typed commands (`:todo-next`, `:todo-prev`) and as static-bindable symbols.

## Suggested keybinding

Add to your `~/.config/helix/init.scm`:

```scheme
(require "cogs/keymaps.scm")

(add-global-keybinding
  (hash "normal"
    (hash "]i" 'todo-next
          "[i" 'todo-prev)))
```

`]i` / `[i` are unbound in Helix's default keymap. The `i` is mnemonic for `@info` — it sits naturally next to `]c` (next comment) in the `]X` motion family.

## Future (v2)

The `]X` motion namespace is reserved for future expansion:

- `]w` / `[w` — `@warning` tags (HACK, WARN, WARNING, TEST, TEMP)
- `]E` / `[E` — `@error` tags (BUG, FIXME, ISSUE, XXX, FIX, SAFETY, ...)
- `]h` / `[h` — `@hint` tags (HINT, MARK, PASSED, STUB, MOCK, TIP)

Other planned features: multi-buffer/project-wide navigation, picker UI, count argument support (`3]i` to jump three tags), configurable tag set.