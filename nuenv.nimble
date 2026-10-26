# Package

version       = "1.0.0"
author        = "Undeadguy"
description   = "A CLI which creates python-env activation file for nushell"
license       = "GPL-3.0-or-later"
srcDir        = "src"
bin           = @["nuenv"]


# Dependencies

requires "nim >= 2.2.12"
requires "nimbra"
requires "results"
