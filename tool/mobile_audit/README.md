# Mobile text audit

Finds text that is cut off on phones: every page of every role, the public
pages and the main dialogs, drawn at 360 and 390 px wide (and a tall 390 px
pass), at the normal and a larger phone font size (1.3x), with Roboto. SAIS
asks for 'Inter', which it doesn't bundle, so phones and browsers draw Roboto.

    flutter test tool/mobile_audit/mobile_audit_test.dart --update-goldens

- `out/report.md`: per page, text that was ellipsized or cut at its line
  limit (CUT), one-line text wider than its box (WIDE) and overflows with
  the line of SAIS code that made the widget (OVERFLOW).
- `out/*.png`: the screens at 390 px (`_n` normal, `_l` larger font, `_t`
  and `_tl` tall). `out/` is git-ignored.
- Text with no font family (some dropdowns and button labels) is drawn with
  the test font here (black bars), which is far wider than Roboto, so the
  report skips it; judge those from the pictures.
- Not part of CI (`tool/` isn't tested). Don't run other Flutter commands
  while it runs.
