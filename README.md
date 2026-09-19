# todo.hx

A plugin for [Helix](https://helix-editor.com/) that adds navigation commands to jump between info-level comment tags (TODO, NOTE, PERF, etc.) in your code.

## Features

- **`:todo-next`** — select the next info-level comment tag in the current buffer
- **`:todo-prev`** — select the previous info-level comment tag in the current buffer

The plugin detects tags through the Tree-sitter `comment` grammar that Helix injects into your language's comments (the same grammar that powers Helix's `@info` tag highlighting), via the Steel `query-document` pipeline.

### Recognized tags

The info vocabulary from Helix's `comment/highlights.scm` `@info` capture, mirrored in the plugin's query:

```
INFO  NOTE  TODO  TO-DO  PERF  OPTIMIZE  PERFORMANCE  QUESTION  ASK  REVIEW  PR  CR
```

Tags are matched structurally on the comment grammar's `tag`/`name` nodes — `AUTODOC` or other words merely containing a tag name are not matches.

### Behavior

Mirrors Helix's built-in `goto_next_comment` / `goto_prev_comment` (`]c` / `[c`) motions, applied to info tags:

- The exact tag range is **selected** (like `]c` selects the whole comment): forward places the cursor at the tag's end, backward at its start
- Strict byte-position comparison: a cursor on a tag never stays on that tag
- No wrap-around: at the last/first tag, the selection stays put silently
- Silent no-op when no match, no parser, or no comment injection
- Count support with a keybinding prefix (`3]i` jumps three tags)
- Multi-cursor: every selection transforms independently; cursors without a target stay put
- The pre-motion selection is pushed to the jumplist — `<C-o>` jumps back
- No side effects on registers, search state, or document content

### Limitations

- Requires a Tree-sitter parser for the buffer **and** a `comment` language injection (most languages configure this via their `injections.scm`; buffers without it silently no-op)
- Tags in doc comments (`/// TODO` in Rust) are not detected: doc comments inject `markdown-rustdoc`, not the `comment` grammar — consistent with Helix's own tag highlighting. Tags inside code blocks within doc comments are still found
- The query mirrors Helix's current tag list; it is a copy, not loaded from Helix's runtime at edit time
- Only the current buffer is navigated (no cross-buffer/project-wide navigation)

## Installation

Install the package with [forge](https://github.com/mystborn/forge) (the Steel package manager):

```
forge install todo.hx
```

Then add to your `~/.config/helix/helix.scm`:

```scheme
(require "todo.hx/navigation.scm")
(provide todo-next todo-prev)
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

Other planned features: multi-buffer/project-wide navigation, picker UI, configurable tag set.
