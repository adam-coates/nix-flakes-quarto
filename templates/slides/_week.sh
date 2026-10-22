# Shared helpers for build / render / deploy. Sourced, not run.

# Turn 3, 03, week-03 or week-03-psychophysics into the actual folder name.
# Prints nothing and returns 1 if no such folder exists.
resolve_week() {
  local given="$1" week

  if [[ ${given#week-} =~ ^[0-9]{1,2}$ ]]; then
    printf -v week 'week-%02d' "$((10#${given#week-}))"
  else
    week="$given"
  fi

  local dir
  dir=$(find . -maxdepth 1 -type d -name "${week}*" -printf '%f\n' | sort | head -1)
  [[ -n $dir ]] || return 1
  printf '%s' "$dir"
}

# Quarto names every output after its input, so each week's handout arrives as
# index.pdf: a dozen identically named files once students download them. Rename
# each to its week (week-01.pdf) so it still says what it is out of its folder.
name_handouts() {
  local pdf dir
  while IFS= read -r pdf; do
    dir=$(dirname "$pdf")
    mv -f "$pdf" "$dir/$(basename "$dir").pdf"
  done < <(find _site -mindepth 2 -name index.pdf)
}
