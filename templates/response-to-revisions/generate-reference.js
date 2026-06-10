const fs = require("fs");
const {
  Document,
  Packer,
  Paragraph,
  TextRun,
  HeadingLevel,
  AlignmentType,
} = require("docx");

// Build a reference.docx with custom character/paragraph styles
// that Pandoc's docx writer will pick up via --reference-doc.
//
// Pandoc maps custom Div classes → paragraph styles and
// custom Span classes → character styles by name.
// Our Lua filter sets these style names on the AST elements.

const doc = new Document({
  styles: {
    default: {
      document: {
        run: {
          font: "Arial",
          size: 20, // 10pt in half-points
          color: "212121",
        },
        paragraph: {
          spacing: { after: 120 },
        },
      },
    },
    paragraphStyles: [
      // Override built-in headings to match the original doc
      {
        id: "Heading1",
        name: "Heading 1",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 24, bold: true, font: "Arial", color: "000000" },
        paragraph: {
          spacing: { before: 240, after: 120 },
          outlineLevel: 0,
        },
      },
      {
        id: "Heading2",
        name: "Heading 2",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 20, bold: true, font: "Arial", color: "000000" },
        paragraph: {
          spacing: { before: 200, after: 80 },
          outlineLevel: 1,
        },
      },
      {
        id: "Heading3",
        name: "Heading 3",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { size: 20, bold: true, font: "Arial", color: "000000" },
        paragraph: {
          spacing: { before: 160, after: 80 },
          outlineLevel: 2,
        },
      },
      // Custom paragraph styles for our div classes
      {
        id: "ReviewerComment",
        name: "Reviewer Comment",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: "Arial", size: 20, color: "212121" },
        paragraph: { spacing: { after: 120 } },
      },
      {
        id: "AuthorResponse",
        name: "Author Response",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: "Arial", size: 20, color: "2A6099" },
        paragraph: { spacing: { after: 120 } },
      },
      {
        id: "ManuscriptCitation",
        name: "Manuscript Citation",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: "Arial", size: 20, color: "729FCF", italics: true },
        paragraph: { spacing: { after: 120 } },
      },
      {
        id: "FigCaption",
        name: "Fig Caption",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: "Arial", size: 20, color: "2A6099" },
        paragraph: { spacing: { after: 120 } },
      },
    ],
    characterStyles: [
      // Inline spans
      {
        id: "ResponseInline",
        name: "Response Inline",
        run: { color: "2A6099" },
      },
      {
        id: "CitationInline",
        name: "Citation Inline",
        run: { color: "729FCF", italics: true },
      },
    ],
  },
  sections: [
    {
      properties: {
        page: {
          size: { width: 12240, height: 15840 },
          margin: { top: 1134, right: 1134, bottom: 1134, left: 1134 },
        },
      },
      children: [
        // Sample content using each style so they're preserved in the docx
        new Paragraph({
          heading: HeadingLevel.HEADING_1,
          children: [new TextRun("Heading 1")],
        }),
        new Paragraph({
          heading: HeadingLevel.HEADING_2,
          children: [new TextRun("Heading 2")],
        }),
        new Paragraph({
          heading: HeadingLevel.HEADING_3,
          children: [new TextRun("Heading 3")],
        }),
        new Paragraph({
          style: "ReviewerComment",
          children: [new TextRun("Reviewer comment text.")],
        }),
        new Paragraph({
          style: "AuthorResponse",
          children: [new TextRun("Author response text.")],
        }),
        new Paragraph({
          style: "ManuscriptCitation",
          children: [new TextRun("Manuscript citation text.")],
        }),
        new Paragraph({
          style: "FigCaption",
          children: [new TextRun("Figure caption text.")],
        }),
        new Paragraph({
          children: [
            new TextRun("Normal text with "),
            new TextRun({ text: "response inline", style: "ResponseInline" }),
            new TextRun(" and "),
            new TextRun({ text: "citation inline", style: "CitationInline" }),
            new TextRun("."),
          ],
        }),
      ],
    },
  ],
});

Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync("custom-reference.docx", buffer);
  console.log("Created custom-reference.docx");
});
