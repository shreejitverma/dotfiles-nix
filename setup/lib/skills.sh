#!/bin/bash
#
# skills.sh: the agent skills this repository owns, sourced rather than executed.
#
# Every directory under files/skills that holds a SKILL.md is a skill this repo
# ships. files/bin/ic-link links each one and files/bin/ic-doctor checks each
# one, so adding a skill (for example one promoted by the learn-eval skill) needs
# no list edit anywhere. Both callers pass the checkout they run from, so the set
# tracks the code version being run, the way a hard-coded list would; ic-link
# still points the durable links at the declared dotfilesDir.
#
# Skills owned by other repositories (gh-axi, no-mistakes, stow, ...) are listed
# explicitly by each caller, because their source lives outside this checkout.

ic_owned_skills() { # <repo root> -> one skill name per line, in glob (sorted) order
  local d
  for d in "$1"/files/skills/*/; do
    [ -f "${d}SKILL.md" ] || continue
    d=${d%/}
    printf '%s\n' "${d##*/}"
  done
}
