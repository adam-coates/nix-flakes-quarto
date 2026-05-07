## Quarto example flake

`example.qmd` -> example quarto file

`zotero.lua` -> lua filter to convert better bibtex citations to 'live' Zotero citations in odt format.

Taken from: [https://retorque.re/zotero-better-bibtex/exporting/zotero.lua](https://retorque.re/zotero-better-bibtex/exporting/zotero.lua) [https://retorque.re/zotero-better-bibtex/exporting/pandoc/index.html](https://retorque.re/zotero-better-bibtex/exporting/pandoc/index.html)

## Pandoc

It's possible to also convert to odt/ docx format using pandoc itself: 

```bash
pandoc example.qmd -o example.odt --lua-filter=zotero.lua
```
