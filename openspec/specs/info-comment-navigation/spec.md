# info-comment-navigation Specification

## Purpose

Let the user jump the cursor to the nearest info-level comment tag (TODO, NOTE, INFO) in the current buffer, in both forward and backward directions, mirroring the behavior of Helix's built-in `goto_next_comment` / `goto_prev_comment` motions but scoped to info-level tags.

## Requirements

### Requirement: Forward navigation to next info-level tag

The plugin SHALL provide a command `todo-next` that moves the cursor to the nearest info-level comment tag whose line is strictly after the cursor's current line. "Info-level comment tag" means any comment containing the word `TODO`, `NOTE`, or `INFO` matched with word boundaries (via `\b(TODO|NOTE|INFO)\b` regex against the comment node's text).

#### Scenario: Jump to next TODO comment

- **WHEN** the cursor is on a line before a comment containing the word `TODO` and the user invokes `todo-next`
- **THEN** the cursor moves to the first non-whitespace character of the line containing that `TODO` comment

#### Scenario: Jump over non-info comments

- **WHEN** the buffer contains comments that do not contain an `@info`-level tag (e.g. a plain `// hello` comment) and a later comment contains `TODO`, and the user invokes `todo-next`
- **THEN** the cursor skips the plain comment and lands on the line of the comment containing `TODO`

#### Scenario: Cursor lands on first non-whitespace character

- **WHEN** `todo-next` targets an indented comment line (e.g. a `TODO` inside a block whose leading whitespace is non-zero)
- **THEN** the cursor lands on the first non-whitespace character of the target line, not at column 0

#### Scenario: Tie-break by wider span

- **WHEN** two `@info` captures start on the same line and no earlier line holds an `@info` capture, and the user invokes `todo-next`
- **THEN** the cursor lands on that line (the tie-break between captures on the same line is deferred to v2; the cursor SHALL land on the line, not fail)

#### Scenario: No match forward

- **WHEN** the cursor is on or after the last line holding an `@info` capture and the user invokes `todo-next`
- **THEN** the cursor does not move and no status message is displayed

#### Scenario: Buffer with no tree-sitter parser

- **WHEN** the current buffer has no tree-sitter syntax tree available (e.g. a plain-text file with no language configured) and the user invokes `todo-next`
- **THEN** the cursor does not move and no status message is displayed

### Requirement: Backward navigation to previous info-level tag

The plugin SHALL provide a command `todo-prev` that moves the cursor to the nearest info-level comment tag whose line is strictly before the cursor's current line, symmetrical to `todo-next`.

#### Scenario: Jump to previous TODO comment

- **WHEN** the cursor is on a line after a comment containing `TODO` and the user invokes `todo-prev`
- **THEN** the cursor moves to the first non-whitespace character of the line containing that `TODO` comment

#### Scenario: No match backward

- **WHEN** the cursor is on or before the first line holding an `@info` capture and the user invokes `todo-prev`
- **THEN** the cursor does not move and no status message is displayed

### Requirement: No wrap-around at buffer boundary

The plugin SHALL NOT wrap the cursor to the opposite end of the buffer when no further matches exist in the requested direction. This matches the behavior of Helix's `goto_next_comment` / `goto_prev_comment` and differs from `search`/`search_next` which wrap by default.

#### Scenario: At last tag, no wrap forward

- **WHEN** the cursor is on the line of the last `@info` capture in the buffer and the user invokes `todo-next`
- **THEN** the cursor does not move and no "Wrapped around" message is displayed

#### Scenario: At first tag, no wrap backward

- **WHEN** the cursor is on the line of the first `@info` capture in the buffer and the user invokes `todo-prev`
- **THEN** the cursor does not move and no "Wrapped around" message is displayed

### Requirement: Strict direction comparison

The line selection for `todo-next` SHALL consider only target lines strictly greater than the cursor's current line; `todo-prev` SHALL consider only target lines strictly less than the cursor's current line. A cursor already on a tag's line SHALL NOT result in staying on that line when invoking `todo-next` or `todo-prev`.

#### Scenario: Cursor on a tag line, invoking next

- **WHEN** the cursor is on the line of an `@info` capture, there is a later `@info` capture on a different line, and the user invokes `todo-next`
- **THEN** the cursor moves to the later capture's line, not staying on the current line

### Requirement: No side effects on editor state

Invoking `todo-next` or `todo-prev` SHALL NOT modify any editor register, search state, selection state, or document content. The only observable mutation SHALL be the cursor position change performed by the underlying `goto-line` / `goto-first-nonwhitespace` calls.

#### Scenario: Registers and search state preserved

- **WHEN** the user has an active search register content (e.g. `/` register holding a previous search pattern) and invokes `todo-next`
- **THEN** the `/` register content, `last_search_register`, and the user's current selection state remain unchanged after the jump

### Requirement: Tag identification via tree walk and rope-regex

The plugin SHALL identify info-level tags by walking the document's root tree-sitter tree to find comment nodes (`line_comment`, `block_comment`, `comment`, `doc_comment`) and matching their rope text against a word-boundary regex `\b(TODO|NOTE|INFO)\b`. The plugin SHALL NOT use `query-document` or `tsmatch-capture` — the Steel boxed-callback FFI cannot reliably return a pre-compiled `TSQuery` to Rust's query pipeline (verified during implementation).

#### Scenario: New tag added to plugin regex

- **WHEN** a future plugin release adds a new tag (e.g. `PERF`) to the regex and the user invokes `todo-next` against a buffer containing that new tag
- **THEN** the plugin recognizes the new tag after the plugin update

### Requirement: Dual invocation as typed command and static keybinding

The plugin SHALL expose `todo-next` and `todo-prev` such that both are invokable as typed commands (`:todo-next`, `:todo-prev`) and bindable as static command symbols (`'todo-next`, `'todo-prev`) in user keymaps. The plugin SHALL NOT ship a default keybinding; users configure their own via Helix's Steel `add-global-keybinding`.

#### Scenario: Invoked as typed command

- **WHEN** the user types `:todo-next` in the Helix command prompt and presses Enter
- **THEN** the plugin's `todo-next` function executes, moving the cursor per the forward-navigation requirement

#### Scenario: Bound to a custom key

- **WHEN** the user has added `(add-global-keybinding (hash "normal" (hash "]i" 'todo-next)))` to their `init.scm` and presses `]i` in normal mode
- **THEN** the plugin's `todo-next` function executes, equivalent to typing `:todo-next`

### Requirement: Silent no-match behavior

When no match is found in the requested direction, neither `todo-next` nor `todo-prev` SHALL emit a status message, error, or warning. The cursor SHALL remain at its current position silently. This matches the silence of `goto_next_comment` and differs from `search`, which emits "No more matches".

#### Scenario: No match in empty buffer

- **WHEN** the current buffer is empty and the user invokes `todo-next`
- **THEN** the cursor does not move and the status line shows no new message from the plugin

#### Scenario: No match in buffer with comments but no info tags

- **WHEN** the current buffer contains comments but none contain an `@info`-level tag and the user invokes `todo-next`
- **THEN** the cursor does not move and the status line shows no new message from the plugin
