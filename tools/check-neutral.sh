#!/usr/bin/env bash
# Check that this repository stays independent of the cloud providers: no
# provider names, CLIs, SDKs or addresses in scripts, configuration or text.
# Everything that knows a provider belongs into that provider's repository.
# The only exception is the note on Overture Maps in 10-analytics: its data
# lies in a public bucket of a provider and needs no account.
# Runs in GitHub Actions on every push (.github/workflows/check.yml).
# Usage: tools/check-neutral.sh
set -o nounset -o pipefail
cd "$(dirname "$0")/.." || exit 1

# names as whole words, case-insensitive
pattern='\b(aws|amazon|amazonaws|azure|gcp|gcloud|google cloud|googleapis|boto3|botocore)\b'
allowed='overture'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -t files < <(git ls-files --cached --others --exclude-standard)
else
  mapfile -t files < <(find . -type f -not -path './.git/*' -not -path './.state/*' -printf '%P\n')
fi
files=("${files[@]/#tools\/check-neutral.sh}")   # this file names the providers on purpose

findings=$(for file in "${files[@]}"; do
  [[ -n "$file" && -f "$file" ]] || continue
  grep --with-filename --line-number --ignore-case --extended-regexp "$pattern" "$file" \
    | grep --invert-match --ignore-case "$allowed"
done)

if [[ -n "$findings" ]]; then
  printf '%s\n' "$findings"
  printf '\n\033[1;31mProvider references found.\033[0m Move them into the provider repositories.\n' >&2
  exit 1
fi
printf '\033[1;32mOK\033[0m No provider references in %d files.\n' "${#files[@]}"
