# info-comment-navigation Specification

## Purpose

Let the user jump to the nearest info-level comment tag in the current buffer, in both forward and backward directions, mirroring the behavior of Helix's built-in `goto_next_comment` / `goto_prev_comment` motions but scoped to info-level tags.

## Requirements

### Requirement: Forward navigation to next info-level tag

The plugin SHALL provide a command `todo-next` that selects the nearest info-level tag strictly after the cursor's current byte position. An info-level tag SHALL be recognized from Helix's structured comment syntax and SHALL include the configured info vocabulary used by the plugin, initially `INFO`, `NOTE`, `TODO`, `TO-DO`, `PERF`, `OPTIMIZE`, `PERFORMANCE`, `QUESTION`, `ASK`, `REVIEW`, `PR`, and `CR`.

#### Scenario: Select the next TODO tag

- **WHEN** the cursor is before a comment containing `TODO` and the user invokes `todo-next`
- **THEN** the plugin selects the exact Tree-sitter range of the matching tag and places the selection head at its end

#### Scenario: Skip comments without info tags

- **WHEN** the buffer contains a plain comment followed by a comment containing `TODO` and the user invokes `todo-next`
- **THEN** the plugin skips the plain comment and selects the later info tag

#### Scenario: Multiple tags on one line

- **WHEN** multiple info tags occur after the cursor on the same line
- **THEN** the plugin chooses the nearest tag by byte position using deterministic Helix-compatible ordering

#### Scenario: Counted forward navigation

- **WHEN** the user invokes `todo-next` with a count greater than one
- **THEN** the plugin advances through that many successive info-tag targets without wrapping

#### Scenario: No match forward

- **WHEN** there is no info tag with a start byte strictly greater than the cursor position
- **THEN** the selection remains unchanged and no status message is displayed

### Requirement: Backward navigation to previous info-level tag

The plugin SHALL provide a command `todo-prev` that selects the nearest info-level tag strictly before the cursor's current byte position. The selected range SHALL have its head at the beginning of the tag, matching the direction of Helix's previous-object motions.

#### Scenario: Select the previous TODO tag

- **WHEN** the cursor is after a comment containing `TODO` and the user invokes `todo-prev`
- **THEN** the plugin selects the exact Tree-sitter range of the matching tag and places the selection head at its beginning

#### Scenario: Counted backward navigation

- **WHEN** the user invokes `todo-prev` with a count greater than one
- **THEN** the plugin moves through that many successive preceding info-tag targets without wrapping

#### Scenario: No match backward

- **WHEN** there is no info tag with an end byte strictly less than the cursor position
- **THEN** the selection remains unchanged and no status message is displayed

### Requirement: No wrap-around at buffer boundary

The plugin SHALL NOT wrap the selection to the opposite end of the buffer when no further info-tag target exists in the requested direction. This SHALL match Helix's native tree-sitter object motions.

#### Scenario: At last tag, no wrap forward

- **WHEN** the cursor is at or after the last info tag and the user invokes `todo-next`
- **THEN** the selection does not move and no wrapped-around message is displayed

#### Scenario: At first tag, no wrap backward

- **WHEN** the cursor is at or before the first info tag and the user invokes `todo-prev`
- **THEN** the selection does not move and no wrapped-around message is displayed

### Requirement: Strict direction comparison

Forward navigation SHALL consider only targets whose start byte is strictly greater than the current cursor byte. Backward navigation SHALL consider only targets whose end byte is strictly less than the current cursor byte. A target containing or beginning at the current cursor position SHALL not be selected by the corresponding motion.

#### Scenario: Cursor on a tag, invoking next

- **WHEN** the cursor is on an info tag and a later info tag exists
- **THEN** `todo-next` selects the later tag rather than staying on the current tag

#### Scenario: Cursor on a tag, invoking previous

- **WHEN** the cursor is on an info tag and an earlier info tag exists
- **THEN** `todo-prev` selects the earlier tag rather than staying on the current tag

### Requirement: Preserve editor state except for navigation

Invoking `todo-next` or `todo-prev` SHALL not modify registers, search state, or document content. It SHALL update the current selection to the target range and SHALL add the pre-motion selection to the jumplist so the native jump-back behavior remains available.

#### Scenario: Registers and search state preserved

- **WHEN** the user has an active search register and invokes an info navigation command
- **THEN** the search register and last-search state remain unchanged

#### Scenario: Selection follows the target

- **WHEN** a matching info tag is found
- **THEN** the current selection is replaced by the exact target range without changing document content

#### Scenario: Jump-back remains available

- **WHEN** the user invokes an info navigation command and then invokes Helix's jump-back command
- **THEN** Helix returns to the selection that existed before the info navigation

### Requirement: Tag identification via Helix comment syntax

The plugin SHALL identify info tags using Helix's injected `comment` Tree-sitter grammar and the same tag vocabulary as Helix's info highlighting. The preferred path SHALL query injected comment layers through the Steel Tree-sitter API. If that query path is unavailable at runtime, the plugin SHALL use a structured traversal of the injected `comment` tree rather than matching arbitrary host-comment text with a regex.

#### Scenario: Structured tag recognition

- **WHEN** a supported language injects the `comment` grammar for a comment containing `TODO(user)`
- **THEN** the plugin recognizes the `TODO` tag and its exact byte range

#### Scenario: Text that is not a tag

- **WHEN** a comment contains `AUTODOC` or another word that merely includes an info word as a substring
- **THEN** the plugin does not report it as an info tag

#### Scenario: Unsupported parser or injection

- **WHEN** the current buffer has no usable syntax tree or no usable comment injection
- **THEN** the command remains a silent no-op and does not alter the selection

### Requirement: Dual invocation as typed command and static keybinding

The plugin SHALL expose `todo-next` and `todo-prev` such that both are invokable as typed commands (`:todo-next`, `:todo-prev`) and bindable as static command symbols (`'todo-next`, `'todo-prev`) in user keymaps. The plugin SHALL NOT ship a default keybinding; users configure their own via Helix's Steel `add-global-keybinding`.

#### Scenario: Invoked as typed command

- **WHEN** the user types `:todo-next` in the Helix command prompt and presses Enter
- **THEN** the plugin's `todo-next` function executes, moving the cursor per the forward-navigation requirement

#### Scenario: Bound to a custom key

- **WHEN** the user has added `(add-global-keybinding (hash "normal" (hash "]i" 'todo-next)))` to their `init.scm` and presses `]i` in normal mode
- **THEN** the plugin's `todo-next` function executes, equivalent to typing `:todo-next`

### Requirement: Silent no-match behavior

When no match is found in the requested direction, neither `todo-next` nor `todo-prev` SHALL emit a status message, error, or warning. The cursor and selection SHALL remain unchanged silently.

#### Scenario: No match in empty buffer

- **WHEN** the current buffer is empty and the user invokes `todo-next`
- **THEN** the selection does not move and no new status message is displayed

#### Scenario: No match in buffer with no info tags

- **WHEN** the current buffer contains comments but no recognized info tags
- **THEN** the selection does not move and no status message is displayed
