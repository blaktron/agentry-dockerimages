// The design families' fixture of scripts/check.sh --typst-image: a block per
// family the report designs may name (agentry-notes plans/report-designs.md,
// D3, D13; agentry-dockerimages#58), set in that family, in regular,
// bold, italic and bold italic, with a line of Chinese, Arabic and Hindi that
// the family lacks and Noto must draw. The check passes every family of
// fonts.txt whose name does not start with "Noto" as the input `families`
// (separated by "|"), and holds the PDF to embedding each one and the three
// Noto fallbacks.

// Behind every family, the Noto fallback the runner's template uses, colour
// emoji first (see report.typ).
#let fallback = (
  "Noto Color Emoji",
  "Noto Sans SC", "Noto Sans KR", "Noto Sans Arabic", "Noto Sans Hebrew",
  "Noto Sans Thai", "Noto Sans Devanagari", "Noto Sans Bengali",
  "Noto Sans Tamil", "Noto Sans Telugu", "Noto Sans Gujarati",
  "Noto Sans Gurmukhi", "Noto Sans Kannada", "Noto Sans Malayalam",
  "Noto Sans Oriya", "Noto Sans Sinhala", "Noto Sans Symbols",
  "Noto Sans Symbols 2", "Noto Sans Math",
)

#let families = sys.inputs.at("families", default: "").split("|").filter(f => f != "")
#assert(families.len() > 0, message: "pass the families as --input families=A|B|…")

#set document(title: "Report design families")
#set page(paper: "a4", margin: 16mm)
#set text(font: ("Noto Sans", ..fallback), size: 10pt, lang: "en")

= Report design families

#for family in families {
  block(breakable: false, below: 10pt, {
    set text(font: (family, ..fallback))
    heading(level: 2, family)
    [Regular: The quick brown fox jumps over the lazy dog, 0123456789. \
     *Bold: Findings by severity, 14 open and 3 fixed.* \
     _Italic: The review was written by an agent._ \
     *_Bold italic: Rotate the gateway API key._* \
     Noto behind it: 支付服务的安全审查 · مراجعة أمان خدمة المدفوعات · भुगतान सेवा की सुरक्षा समीक्षा]
  })
}
