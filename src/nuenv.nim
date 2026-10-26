import nimbra
import std/[paths, dirs, files]
import results
from strutils import `%`, replace

const ScriptFilename = Path("activate.nu")

const OverlayTemplate = """
# nuenv activation module:
# - Activate with `overlay use activate.nu`
# - Deactivate with `deactivate`
#
# To customize the overlay name, call `overlay use activate.nu as foo`, but then `deactivate` won't work —
# you'd need to run `overlay hide foo` manually. Do not activate with `use activate.nu *`; that does not
# create an overlay and deactivation will fail.

module warning {
  export-env {
    const file = path self
    error make -u {
      msg: $"`($file | path basename)` is meant to be used with `overlay use`, not `source`"
    }
  }
}

use warning

export-env {
  let nu_ver = (version | get version | split row '.' | take 2 | each { into int })
  if $nu_ver.0 == 0 and $nu_ver.1 < 106 {
    error make {
      msg: 'nuenv Nushell activation requires Nushell 0.106 or greater.'
    }
  }

  def has-env [...names] {
    $names | each {|n| $n in $env } | all {|i| $i }
  }

  def is-env-true [name: string] {
    if (has-env $name) {
      let val = ($env | get --optional $name)
      if ($val | describe) == 'bool' {
        $val
      } else {
        not ($val | is-empty)
      }
    } else {
      false
    }
  }

  let virtual_env = __VIRTUAL_ENV__
  let bin = __BIN_NAME__
  let path_name = if (has-env 'Path') { 'Path' } else { 'PATH' }
  let venv_path = ([$virtual_env $bin] | path join)
  let new_path = ($env | get $path_name | prepend $venv_path)
  let virtual_env_prompt = __VIRTUAL_PROMPT__
  let new_env = {
    $path_name: $new_path
    VIRTUAL_ENV: $virtual_env
    VIRTUAL_ENV_PROMPT: $virtual_env_prompt
  }
  let old_prompt_command = if (has-env 'PROMPT_COMMAND') { $env.PROMPT_COMMAND } else { '' }
  let new_env = if (is-env-true 'VIRTUAL_ENV_DISABLE_PROMPT') {
    $new_env
  } else {
    let virtual_prefix = $'(char lparen)($virtual_env_prompt)(char rparen) '
    let new_prompt = if (has-env 'PROMPT_COMMAND') {
      if ('closure' in ($old_prompt_command | describe)) {
        {|| $'($virtual_prefix)(do $old_prompt_command)' }
      } else {
        {|| $'($virtual_prefix)($old_prompt_command)' }
      }
    } else {
      {|| $'($virtual_prefix)' }
    }
    $new_env | merge { PROMPT_COMMAND: $new_prompt VIRTUAL_PREFIX: $virtual_prefix }
  }
  load-env $new_env
}

export alias pydoc = python -m pydoc
# If deactivate errors "not an active overlay": activate with `overlay use activate.nu` not `use activate.nu *`; for custom names use `overlay hide NAME`
export alias deactivate = overlay hide activate
"""

const SourceTemplate = """
# Activate with: source activate.nu
# Deactivate with: deactivate
#
# This is the source-style activator. Prefer `overlay use activate.nu` when you can
# (generate with nuenv without --source); overlay deactivation is cleaner.

def --env deactivate [] {
  def has-env [name: string] { $name in $env }

  if 'VIRTUAL_ENV_OLD_PATH' in $env {
    let path_name = if 'VIRTUAL_ENV_OLD_PATH_NAME' in $env {
      $env.VIRTUAL_ENV_OLD_PATH_NAME
    } else if (has-env 'Path') {
      'Path'
    } else {
      'PATH'
    }
    load-env { $path_name: $env.VIRTUAL_ENV_OLD_PATH }
    hide-env VIRTUAL_ENV_OLD_PATH
    hide-env -i VIRTUAL_ENV_OLD_PATH_NAME
  }

  if 'VIRTUAL_ENV_OLD_PYTHONHOME' in $env {
    $env.PYTHONHOME = $env.VIRTUAL_ENV_OLD_PYTHONHOME
    hide-env VIRTUAL_ENV_OLD_PYTHONHOME
  }

  hide-env -i VIRTUAL_ENV
  hide-env -i VIRTUAL_ENV_PROMPT
}

try { deactivate }

let virtual_env = __VIRTUAL_ENV__
let bin = __BIN_NAME__
let path_name = if 'Path' in $env { 'Path' } else { 'PATH' }
let venv_path = ([$virtual_env $bin] | path join)

$env.VIRTUAL_ENV = $virtual_env
$env.VIRTUAL_ENV_PROMPT = __VIRTUAL_PROMPT__
$env.VIRTUAL_ENV_OLD_PATH = ($env | get $path_name)
$env.VIRTUAL_ENV_OLD_PATH_NAME = $path_name
load-env { $path_name: (($env | get $path_name) | prepend $venv_path) }

if 'PYTHONHOME' in $env {
  $env.VIRTUAL_ENV_OLD_PYTHONHOME = $env.PYTHONHOME
  hide-env PYTHONHOME
}
"""

type
  VenvLayout = object
    venvRoot: Path
    binDir: Path
    binName: string

proc nuSingleQuote(s: string): string =
  ## Nushell single-quoted string; escape embedded single quotes by doubling.
  "'" & s.replace("'", "''") & "'"

proc nuDoubleQuote(s: string): string =
  '"' & s.replace("\\", r"\\").replace("\"", "\\\"") & '"'

proc fillTemplate(tmpl, virtualEnv, binName, prompt: string): string =
  result = tmpl
  result = result.replace("__VIRTUAL_ENV__", nuSingleQuote(virtualEnv))
  result = result.replace("__BIN_NAME__", nuDoubleQuote(binName))
  result = result.replace("__VIRTUAL_PROMPT__", nuSingleQuote(prompt))

proc resolveVenv(input: Path): Result[VenvLayout, string] =
  let resolved =
    if input.isAbsolute:
      input
    else:
      absolutePath(input)

  if not dirExists(resolved):
    return err("dir $1 not exists" % [$resolved])

  let part = $resolved.lastPathPart
  if part == "bin" or part == "Scripts":
    return ok(
      VenvLayout(venvRoot: resolved.parentDir, binDir: resolved, binName: part)
    )

  when defined(windows):
    const order = ["Scripts", "bin"]
  else:
    const order = ["bin", "Scripts"]

  for name in order:
    let candidate = resolved / Path(name)
    if dirExists(candidate):
      return ok(VenvLayout(venvRoot: resolved, binDir: candidate, binName: name))

  err(
    "something wrong with venv dir, neither bin nor Scripts exists under $1" %
      [$resolved]
  )

proc createEnv(
  args: seq[string],
  source {.help: "Generate source-style script for `source activate.nu`".}: bool =
    false,
  overlay {.help: "Generate overlay module for `overlay use activate.nu` (default)".}: bool =
    false,
  force {.short: 'f', help: "Overwrite existing activate.nu".}: bool = false,
): Result[void, string] {.help: "Create a Nushell activate.nu for a Python virtualenv".} =
  if args.len != 1:
    return err("expected exactly one positional argument: path to venv (or its bin/Scripts)")

  if source and overlay:
    return err("flags --source and --overlay are mutually exclusive")

  let useSource = source # default (and --overlay) → overlay module
  let layout = ?resolveVenv(Path(args[0]))

  let scriptPath = layout.binDir / ScriptFilename
  if fileExists(scriptPath) and not force:
    return err("file $1 already exists (use --force to overwrite)" % [$scriptPath])

  let virtualEnvAbs = $absolutePath(layout.venvRoot)
  let prompt = $layout.venvRoot.lastPathPart
  let tmpl = if useSource: SourceTemplate else: OverlayTemplate
  let script = fillTemplate(tmpl, virtualEnvAbs, layout.binName, prompt)

  try:
    writeFile($scriptPath, script)
  except CatchableError as e:
    return err("failed to write $1: $2" % [$scriptPath, e.msg])

  let mode = if useSource: "source" else: "overlay"
  stdout.writeLine(
    "file $1 created successfully! ($2 mode)" % [$scriptPath, mode]
  )
  ok()

when isMainModule:
  defineCommand(createEnv, mainCmd)
  mainCmd.argLimit = exact(1)
  mainCmd.executeOrQuit()
