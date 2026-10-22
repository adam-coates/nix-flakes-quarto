# spinner

A fruit-machine / random-spinner shortcode for Quarto **revealjs** decks.
Give it a list of options and it hands them out one at a time, at random, with
a proper slot-machine spin. Each option can come up **only once**.

## Install

Copy the `_extensions/spinner` folder next to your `.qmd` (or into the project
root), or from another project:

```bash
quarto install extension /path/to/output/_extensions/spinner
```

Then switch it on in the document header:

```yaml
format: revealjs
filters:
  - spinner
revealjs-plugins:
  - spinner
```

## Use

````markdown
::: {#draw .spinner groups="9" duration="6s" theme="casino"}
- Predictive coding in visual cortex
- Neural correlates of consciousness
- Resting-state networks and cognition
:::
````

Every bullet is one option. Press **SPIN** once per group: the reel spins, lands
on an option, and the result is added to the list beside it. Clicking the reel
itself spins too, which is an easier target when presenting.

Mirror the results onto a later slide with:

````markdown
::: {.spinner-summary for="draw" columns="2"}
:::
````

(`for` must match the `#id` of the spinner div.)

## How the randomness works

The option list is shuffled once when the deck loads, using
`crypto.getRandomValues` with modulo bias rejected. Each spin takes the next
card off that fixed deck, so no option can be drawn twice and the spin is an
animation of a draw that has already been made. Drawn options stay visible on
the reel, struck through, so the audience can see they are out of play.

**Reset** re-shuffles from scratch and clears the results.

## Options

Set them on the div, or globally under `spinner:` in the YAML header. Div
attributes win over the document defaults.

| Option          | Default       | Meaning |
|-----------------|---------------|---------|
| `groups`        | one per option | Number of draws (`"9"`) or explicit labels (`"Ana, Ben, Kim"`). |
| `group-label`   | `Group`       | Word put in front of the number when `groups` is a count. |
| `duration`      | `6s`          | Length of one spin. Accepts `6s`, `6000`, `6000ms`. |
| `cycles`        | `3`           | How many complete passes of the option list go by before it stops. Every option is on the reel, so this is how many times each one is seen. |
| `rows`          | `3`           | Visible rows in the window (odd numbers; the middle one is the result). |
| `row-height`    | `110px`       | Height of one row. |
| `font-size`     | `26px`        | Option text size on the reel. |
| `blur`          | `2`           | Maximum motion blur in px. `blur="0"` turns it off for maximum legibility. |
| `sound`         | `true`        | Ticking while spinning and a chime on landing. Also togglable live. |
| `theme`         | `classic`     | `classic`, `light`, `dark`, `casino`, `minimal`. |
| `accent`        | theme's       | Button colour, any CSS colour. |
| `results`       | `right`       | `right`, `below`, or `none`. |
| `results-title` | `Assignments` | Heading over the results list. |
| `button-label`  | `SPIN`        | Text on the button. |
| `keep-drawn`    | `true`        | Keep drawn options on the reel, struck through. `false` removes them. |
| `shuffle-reel`  | `false`       | `false` keeps the reel in the order you listed the options, like a real reel. `true` reshuffles the visible order each spin. |

Slower and fully legible:

```markdown
::: {.spinner duration="9s" cycles="2" blur="0" rows="5"}
```

Fast and loud:

```markdown
::: {.spinner duration="3.5s" cycles="5" theme="casino" accent="#f0a500"}
```

## Notes

- Several spinners can live in one deck; each keeps its own deck and results.
- Each draw fires a `spinner:drawn` DOM event with `{group, option, index}`,
  if you ever want to hang something else off it.
- Fine styling is all CSS custom properties (`--sp-accent`, `--sp-row-h`,
  `--sp-band`, …) on `.spinner-machine`, so a deck's own SCSS can override any
  of it.
