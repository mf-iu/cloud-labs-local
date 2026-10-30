#!/usr/bin/env bash

# Check that this repository stays independent of the cloud providers: no
# provider names, CLIs, SDKs or addresses in scripts, configuration or text.
# Everything that knows a provider belongs into that provider's repository.
# The only exception is the note on Overture Maps in 10-analytics: its data
# lies in a public bucket of a provider and needs no account.
# Runs in GitHub Actions on every push (.github/workflows/check.yml).
#
# Usage: tools/check-neutral.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

set -o nounset -o pipefail
# $0 is the path of this script: work in the folder of the repository
cd "$(dirname "$0")/.." || exit 1

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# names as whole words, case-insensitive
# Regular expression: \b marks the start or end of a word, | separates the
# alternatives
pattern='\b(aws|amazon|amazonaws|azure|gcp|gcloud|google cloud|googleapis|boto3|botocore)\b'
allowed='overture'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# In a Git repository: all files that git knows or would add, without those in
# .gitignore
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # mapfile reads the lines of the output into the array files; <(cmd) passes
    # the output of cmd like a file
    mapfile -t files < <(git ls-files --cached --others --exclude-standard)
else
    # Without Git: all files except .git and .state; %P prints the path without
    # ./
    mapfile -t files < <(find . -type f -not -path './.git/*' -not -path './.state/*' -printf '%P\n')
fi

# ${files[@]/#x} removes x from the start of every element: the entry of this
# file becomes empty and is skipped below
files=("${files[@]/#tools\/check-neutral.sh}")   # this file names the providers on purpose

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The output of the whole loop goes into findings: matching lines as
# file:line:text, without the allowed ones
findings=$(for file in "${files[@]}"; do
    [[ -n "$file" && -f "$file" ]] || continue
    grep --with-filename --line-number --ignore-case --extended-regexp "$pattern" "$file" \
        | grep --invert-match --ignore-case "$allowed"
    done)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ -n "$findings" ]]; then
    printf '%s\n' "$findings"
    printf '\n\033[1;31mProvider references found.\033[0m Move them into the provider repositories.\n' >&2
    exit 1
fi

# ${#files[@]} is the number of elements in the array
printf '\033[1;32mOK\033[0m No provider references in %d files.\n' "${#files[@]}"
