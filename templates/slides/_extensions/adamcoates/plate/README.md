# plate

A Reveal.js theme for teaching decks. Ink on white, Inter Light, one lapis
accent, 16:9, two logos facing the title on the cover. Modelled on Grant
McDermott's
[quarto-revealjs-clean](https://github.com/grantmcdermott/quarto-revealjs-clean):
same restraint, same left-aligned cover, same italic accented sub-headings — but
set in Inter rather than Roboto, on a different palette, and with two logos on
the title slide.

Self-contained: no CDN, no network at render or present time.

## Using it

```yaml
---
title: "Session 3"
subtitle: "Reliability coefficients"
format: plate-revealjs
author:
  - name: Adam Coates
    email: adam.coates@uni-graz.at
    affiliations: University of Graz
---
```

The theme needs `_brand.yml` in the deck's folder — that is where every colour
and the two logos live. Copy it alongside the deck.

## The design, in one paragraph

Nothing on a slide but type. Headings are large and Light (Inter 300) and are
followed by space rather than by a rule; body copy stays at 400 so the back row
of a lecture room can still read it. `h3` is the one recurring flourish: italic,
lapis. Colour appears only where it carries meaning — a link, a defined term, a
wrong answer — and links are coloured but not underlined until you point at them.
Nested list items trade their bullet for a right arrow. Tables get a rule under
the header and one under the last row, and nothing else.

## Colour

Edit `_brand.yml`, not the SCSS. The theme reads Quarto's brand variables
(`$primary`, `$success`, `$body-bg`, …) and derives its tints and borders from
them, so one edit carries through to lists, tables, callouts, boxes, the livepoll
widgets, the countdown timer and the spinner.

| role        | colour    | used for                                       |
| ----------- | --------- | ---------------------------------------------- |
| `primary`   | lapis     | links, `h3`, the cover subtitle, list markers  |
| `secondary` | slate     | captions, affiliations, slide numbers          |
| `tertiary`  | violet    | defined terms                                  |
| `success`   | pine      | correct answers, positive results              |
| `warning`   | amber     | the one thing per slide that matters           |
| `danger`    | claret    | `h4`, wrong answers, caveats, misconceptions   |
| `dark`      | ink       | divider slides, the spinner cabinet            |

Two colours do the visible work — lapis for structure, claret for warnings — and
they are far enough apart in hue that "wrong" can never read as "link". The rest
are a semantic reserve, meant a line at a time.

## Logos

`_brand.yml` → `logo.images.left` / `.right`. A Lua filter copies them into the
title-slide template; a deck can override either with `logo-left:` /
`logo-right:` in its own YAML. They appear on no other slide.

The cover is two columns: the title block left, the logos stacked in a column on
the right, the two centred against each other. So `left` is the upper logo and
`right` the lower one — the names are just the two slots. Stacked rather than
side by side because that is what lets them be big; a row of two on the right
half has half the width to share.

Size comes from `$title-logo-height` / `$title-logo-width` near the top of
`plate.scss`: each logo is fitted into that box with `object-fit: contain`, so
proportions do not matter. Two boxes plus their gap have to fit inside 720px, so
much above 200px starts to crowd.

One thing that will otherwise waste your time: **the box is not what the eye
measures.** Both current logo files carry white margin inside the image —
`left.jpg` spends about 28% of its height on it, `right.png` about 13% — so a mark
always reads smaller than the number in the SCSS, and two logos in equal boxes
look unequal. There is a `.title-logo-left` override compensating for exactly
that; if either file is ever replaced with a tightly cropped version, delete the
override and turn the shared height down.

Supply **dark-on-transparent** artwork; SVG preferred. If the only version you
have is light artwork, set `$logo-plate: true` near the top of `plate.scss` and
each logo gets a small dark plate behind it, sized to the logo.

`logos/` ships with the deck (see `deploy`), because the cover references the
files by relative path.

## Type

Inter v4.1 (Light and Light Italic from v4.66), subsetted to
Latin/Latin-Ext/Greek/punctuation/arrows/maths and inlined as data URIs in the
theme CSS: 300, 300 italic, 400, 400 italic, 500, 600, 700. Nothing is fetched at
present time and `deploy` needs no extra files — a lecture room with no wifi
renders exactly like your laptop.

To change weights or coverage, edit and rerun:

```bash
./_extensions/adamcoates/plate/fonts/build-fonts.sh   # inside the nix shell
```

To change *font*, drop the new `.woff2` files into `fonts/`, adjust the `FACES`
map in that script, rerun it, and update `typography` in `_brand.yml`. A family
without a real Light will need the weights in `plate.scss` moved up to 400/500 —
faux-light is not a thing browsers can do.

## Classes the theme adds

Inline (`[text]{.class}`):

| class       | meaning                              |
| ----------- | ------------------------------------ |
| `.term`     | a term being defined                 |
| `.good`     | correct / it works                   |
| `.alert`    | wrong / careful — `.bad` is an alias |
| `.emph`     | the point of the slide               |
| `.quiet`    | deliberately backgrounded            |
| `.button`   | Beamer-style link button             |
| `.fg`/`.bg` | arbitrary colour via `col="#..."`    |

Blocks (`::: {.class}`):

| class        | meaning                                  |
| ------------ | ---------------------------------------- |
| `.box`       | bordered aside, accent rule on the left  |
| `.box-good`  | worked example, positive result          |
| `.box-alert` | misconception, common error              |
| `.box-term`  | definition                               |
| `.takeaway`  | closing line, rule above it              |

Slides:

| class      | meaning                                               |
| ---------- | ----------------------------------------------------- |
| `.divider` | section break; pair with `background-color="#15181B"` |
| `.smaller` | Quarto's own, restyled                                |

Column splits `.columns3070`, `.columns7030`, `.columns4060`, `.columns6040` and
`.button` keep clean-revealjs' names, so decks port across without edits.

## Extensions pulled onto the palette

livepoll, the countdown timer and the spinner all ship their own colours. The
theme restates them in brand terms so a poll or a draw does not look like a
different deck. Three of those overrides are more contorted than they look, and
all three are commented in place:

- **Poll buttons carry `.reveal .slides` in the selector.** livepoll.css is
  injected *after* the theme, so the obvious `.reveal .poll button` ties on
  specificity and loses. The rule also sets `background` and `color` explicitly —
  leave them off and a bare `<button>` picks up the operating system's widget
  theme, which on a GTK desktop is a solid blue slab.
- **The timer's paused face is matched on a serialised colour.** timer.js writes
  `fill: #fcb` inline whenever the countdown is not running, which is how it sits
  before anyone touches it; inline styles can only be answered with
  `!important`, and the hook has to be the colour itself because the running
  state is the same element with the fill removed.
- **Only the spinner's `classic` preset is re-skinned.** Its look is entirely
  `--sp-*` custom properties, so the overrides are just variables — pinned to
  `.sp-theme-classic` so `theme="casino"` is still loud when you want it.

## Three things that look like bugs and are not

- **`margin: 0` in `_extension.yml`.** Reveal's default 8% margin frames
  anything full-bleed in white. The theme adds the breathing room back as slide
  padding (`$slide-pad-x` / `$slide-pad-y`). It also means a `.absolute` block's
  px coordinates are measured against the full 1280×720 canvas.
- **`.slide-number` rules carry no `.reveal` ancestor.** Reveal appends that
  element to `<body>`, outside `.reveal`; the natural-looking
  `.reveal .slide-number` selector silently never matches.
- **The cover's logos are positioned `absolute`, not `fixed`.** Reveal scales
  `.slides` with a transform, which makes a transformed ancestor the containing
  block for fixed children — `fixed` would pin them to the scaled deck rather
  than the screen.
