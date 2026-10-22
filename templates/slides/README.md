# Slides

Quarto revealjs decks in the plate theme, with live polls, word clouds and
rating scales, a countdown timer, drawing on slides, a laser pointer, animated
annotations and a random spinner, plus a PDF handout of every deck. One folder
per week; everything shared lives once at the root.

## Start

```bash
nix flake init -t github:adam-coates/nix-flakes-quarto#slides   # or copy this folder
git init && git add -A          # nix only sees files git knows about
direnv allow                    # or: nix develop; the first time this also
                                # installs the extensions (needs internet)
git add -A && git commit -m "Start"   # commit _extensions/ to pin their versions
./new-week 01 intro "Introduction"
./render 01                     # http://localhost:8082/week-01-intro/
```

Then once, before the first live poll: set your venue and password hash in
`_quarto.yml` (see [Live polls](#live-polls)).

## Day to day

| command | what it does |
| --- | --- |
| `./new-week 03 [slug] ["Title"]` | new `week-03[-slug]/index.qmd` from `template/week.qmd` |
| `./render 03` | build that week and serve it on :8082 (`./render` for all) |
| `./build 03 [--pdf]` | build only; `--pdf` adds the handout `week-03.pdf` |
| `./deploy [03]` | build with handouts and copy into your site (set `DEST` and `BASE_URL` at the top of `./deploy`) |
| `./install-extensions [--update]` | install missing extensions; `--update` reinstalls all at their latest versions |

Weeks can be given as `3`, `03`, `week-03` or the full folder name.

## Files

```
_quarto.yml      shared settings: formats, plugins, author, poll server
_brand.yml       colours and fonts for slides and handouts
logos/           the title-slide logos (left.jpg, right.png)
template/        week.qmd, the seed ./new-week copies
week-NN-slug/    one folder per deck: index.qmd plus its figures and data
_extensions/     the extensions (below): plate and spinner ship with the
                 template, the rest are installed by ./install-extensions
```

## In a deck

````markdown
::: {.poll #q1}                         <!-- live poll; - [x] marks the answer -->
- [x] right
- [ ] wrong
:::

::: {.wordcloud #today max-words="2"}
:::

::: {.likert #feedback scale="agree-5"} <!-- also agree-7, 0-10, labels="a|b|c" -->
- The pace was right
:::

[this]{.rn-fragment rn-type=underline}  <!-- annotation drawn on the next step -->

::: {.timer #t1 seconds=120 starton=interaction}
:::
````

`template/week.qmd` has a working example of each.

| key | |
| --- | --- |
| Shift+L | live-poll controls (also in the menu, bottom left) |
| Shift+Q | full-screen QR code for the audience's page |
| Alt+R | save the session (poll results, drawings) as `session.json` |
| <kbd>`</kbd> | draw on the slide (Excalidraw) |
| Q | laser pointer |

## Live polls

Polls go through a [seminar](https://github.com/rajgoel/seminar) server
(`seminar: server:` in `_quarto.yml`). Each course needs its own venue
(`seminar: url:`) and a presenter password, stored only as a bcrypt hash:

```bash
nix shell nixpkgs#python3Packages.bcrypt -c python3 -c "import bcrypt;print(bcrypt.hashpw(b'YOURPASS', bcrypt.gensalt(rounds=5, prefix=b'2a')).decode())"
```

Put the output in `seminar: hash:`. Use a password you use nowhere else: the
hash is in every deck's HTML. Each week gets its own room automatically.

To present: open the deck, Shift+L, enter the password, Start. The audience
scans the QR code. After class, Alt+R and move `session.json` into the week's
folder: re-rendering then shows the results on the slides, and `./build --pdf`
puts them in the handout.

Everything about the polls, layouts and chart options:
[seminar-quarto](https://github.com/adam-coates/seminar-quarto).

## Extensions

| extension | from | in `_quarto.yml` |
| --- | --- | --- |
| plate (theme, handout) | ships here, `_extensions/adamcoates/plate` | the `plate-revealjs` / `plate-pdf` formats |
| spinner | ships here, `_extensions/spinner` | filter + plugin |
| livepoll | `adam-coates/seminar-quarto` | filter + plugin |
| timer | `adam-coates/timer-quarto` | filter |
| excalidraw | `parmsam/quarto-excalidraw` | plugin |
| pointer | `quarto-ext/pointer` | plugin |
| roughnotation | `EmilHvitfeldt/quarto-roughnotation` | filter |
| shapes, arrows | `emilhvitfeldt/quarto-shapes`, `quarto-arrows` | filter / shortcode |
| editable | `emilhvitfeldt/quarto-revealjs-editable` | off; see `_quarto.yml` |

The ones with a GitHub repo are listed in `./install-extensions`: add a line
there (and the filter or plugin to `_quarto.yml`) to add another, and
`./install-extensions --update` updates them all. Extensions ship CSS and
JavaScript at fixed URLs, so after updating, hard-reload an open deck
(Ctrl+Shift+R).
