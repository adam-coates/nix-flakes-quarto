# Response-to-Reviewers Quarto Template

A Quarto template for writing response-to-reviewer letters. Outputs to both **PDF** and **DOCX** with color-coded text for reviewer comments, author responses, and manuscript citations.

## Styling

| Element               | Color              | Style        |
|-----------------------|--------------------|--------------|
| Reviewer comments     | Near-black #212121 | Normal       |
| Author responses      | Blue #2A6099       | Normal       |
| Manuscript citations  | Light blue #729FCF | Italic       |
| Headings (Reviewer:)  | Black #000000      | Bold         |
| Comment IDs (R1.1)    | Black #000000      | Bold         |
| Hyperlinks            | Blue #3465A4       |              |

## File Structure

```
quarto-template/
├── response_to_reviewers.qmd         # Main document — edit this
├── preamble.tex                      # LaTeX preamble (PDF only)
├── custom-reference.docx             # Reference styles (DOCX only)
├── generate-reference.js             # Script to regenerate reference.docx
├── _extensions/
│   └── response-letter/
│       ├── _extension.yml
│       └── response-letter.lua       # Lua filter (handles PDF + DOCX)
└── README.md
```

## Rendering

```bash
# PDF output
quarto render response_to_reviewers.qmd --to pdf

# DOCX output
quarto render response_to_reviewers.qmd --to docx

# Both
quarto render response_to_reviewers.qmd
```

## Writing Your Response

Use fenced divs with these classes:

```markdown
::: {.reviewer-comment}
The reviewer's original comment. (black text)
:::

::: {.response}
Your reply. (blue text)
:::

::: {.citation}
*Quoted manuscript text.* (light blue italic)
:::

::: {.figcaption}
**Figure X.** Caption. (blue text)
:::
```

Headings: `#` for reviewer sections, `##` for comment IDs:

```markdown
# Reviewer: 1
## R1.1 {.unnumbered}
## R1.2 {.unnumbered}
### Minor Comments {.unnumbered}
## r1.1 {.unnumbered}
```

Inline color spans for the intro paragraph:

```markdown
Our response is in [blue font]{.response-inline}.
Citations are in [light blue italic]{.citation-inline}.
```

## Customizing the Reference DOCX

If you want to change fonts or colors for DOCX output, edit `generate-reference.js` and re-run:

```bash
node generate-reference.js
```

This regenerates `custom-reference.docx`. Requires `npm install -g docx`.

## Customizing PDF

- **Font**: Change `mainfont` in the YAML header.
- **Colors**: Edit `\definecolor` in `preamble.tex`.
- **Margins**: Edit `geometry` in the YAML header.
