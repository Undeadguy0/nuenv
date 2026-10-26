# nuenv

CLI that writes a Nushell `activate.nu` for an existing Python virtual environment.

`python -m venv` gives you bash/zsh/fish activators. Nushell needs its own file. **nuenv** generates one next to the other activators (`bin/activate.nu` on Unix, `Scripts/activate.nu` on Windows), in either of the two styles people use today.

## Requirements

- [Nim](https://nim-lang.org/) >= 2.2.12 and [nimble](https://github.com/nim-lang/nimble)
- Dependencies (pulled by nimble): [nimbra](https://github.com/Undeadguy0/Nimbra), [results](https://github.com/arnetheduck/nim-results)
- A Python venv that already exists (`python -m venv`, `uv venv`, virtualenv, etc.)
- For **overlay** mode: [Nushell](https://www.nushell.sh/) >= 0.106

## Build

```bash
cd nuenv
nimble build
```

Binary lands as `nuenv` (or `nuenv.exe` on Windows) in the project root.

## Usage

```text
nuenv [--overlay | --source] [-f | --force] <venv-path>
```

`<venv-path>` may be the venv root (`.venv`) or its `bin` / `Scripts` directory.

| Flag | Meaning |
|------|---------|
| *(default)* / `--overlay` | Module for `overlay use activate.nu` (same idea as virtualenv/uv) |
| `--source` | Script for `source activate.nu` |
| `-f` / `--force` | Overwrite an existing `activate.nu` |

`--source` and `--overlay` together are an error.

### Overlay (default)

```nu
nuenv /path/to/.venv
# or: nuenv --overlay -f /path/to/.venv

overlay use /path/to/.venv/bin/activate.nu   # Windows: Scripts\activate.nu
# work...
deactivate
```

Uses a Nushell overlay: env changes (including `PATH`/`Path`, `VIRTUAL_ENV`, prompt prefix) roll back when the overlay is hidden. Do **not** `source` this file; activation is `overlay use`.

### Source

```nu
nuenv --source -f /path/to/.venv

source /path/to/.venv/bin/activate.nu
# work...
deactivate
```

Defines `deactivate` in the current scope and backs up / restores `PATH` (or `Path`) and `PYTHONHOME`. Prefer overlay when you can; source is there for simpler or older workflows.

## What it sets

Both modes typically set:

- `VIRTUAL_ENV` - absolute path to the venv root
- `VIRTUAL_ENV_PROMPT` - directory name of the venv (for prompts)
- Prepend the venv's `bin` or `Scripts` onto `PATH` / `Path`
- Clear `PYTHONHOME` while active (source mode restores it on deactivate)

Overlay mode can prefix `PROMPT_COMMAND` with `(venvname)` unless `VIRTUAL_ENV_DISABLE_PROMPT` is set. Source mode leaves `PROMPT_COMMAND` alone.

## Platform notes

nuenv picks `bin` vs `Scripts` from the host OS and from what actually exists under the venv, so the same project works on Linux and Windows.

## License

GPL-3.0-or-later - see `nuenv.nimble`.