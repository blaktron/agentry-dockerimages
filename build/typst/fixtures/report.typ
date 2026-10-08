// The fixture template of scripts/check.sh --typst-image: report.md (the
// 2026-10-08 prototype's sample, plus a line per further script) rendered
// through the vendored cmarker with the bundled fonts only. It is not the
// runner's template, which is agentry-cli's (plan scratch-and-pdf-reports §5,
// M3), but it holds the two settings that one must: raw-typst is false, so
// the Markdown can never inject Typst code, and every image carries its alt
// text, which a PDF/UA-1 document needs.
#import "@preview/cmarker:0.1.10"

// Colour emoji straight after the text font: the first family that has a
// glyph wins, and the CJK and symbol fonts also draw some emoji (U+26A0,
// U+1F512) in monochrome. Noto Sans itself covers the digits and marks the
// emoji font also has, so those never reach it.
#let fallback = (
  "Noto Color Emoji",
  "Noto Sans SC", "Noto Sans KR", "Noto Sans Arabic", "Noto Sans Hebrew",
  "Noto Sans Thai", "Noto Sans Devanagari", "Noto Sans Bengali",
  "Noto Sans Tamil", "Noto Sans Telugu", "Noto Sans Gujarati",
  "Noto Sans Gurmukhi", "Noto Sans Kannada", "Noto Sans Malayalam",
  "Noto Sans Oriya", "Noto Sans Sinhala", "Noto Sans Symbols",
  "Noto Sans Symbols 2", "Noto Sans Math",
)

#set document(title: "Security Review: Payments Service")
#set page(paper: "a4", margin: 20mm, footer: context align(right, text(size: 8pt,
  counter(page).display("1 of 1", both: true))))
#set text(font: ("Noto Sans", ..fallback), size: 10.5pt, lang: "en")
#show raw: set text(font: ("Noto Sans Mono", ..fallback), size: 8.8pt)
#show raw.where(block: true): block.with(fill: luma(244), inset: 6pt, width: 100%)
#show heading.where(level: 1): set text(font: ("Noto Serif", ..fallback))
#set table(inset: 4pt, stroke: 0.4pt + luma(190))
#show table.cell.where(y: 0): set text(weight: "bold")
// Break over-long tokens, as the prototype did.
#show regex("\\S{36,}"): it => it.text.clusters().join(sym.zws)

#cmarker.render(
  read("report.md"),
  raw-typst: false,
  set-document-title: false,
  scope: (
    image: (path, alt: none, ..args) => figure(
      image(path, alt: if alt == none { path } else { alt }, width: 80%),
      caption: alt,
    ),
  ),
)
