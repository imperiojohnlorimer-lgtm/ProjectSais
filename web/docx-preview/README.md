# Vendored Word viewer

Used by `lib/utils/web_document_view_web.dart` to show a student's `.docx` in the
browser without sending the file to any outside service. Loaded only when a Word
file is previewed.

| File | What | Version | License |
|---|---|---|---|
| `docx-preview.min.js` | docx-preview (docxjs), from the npm package `docx-preview` | 0.4.1 | Apache-2.0 (`LICENSE-docx-preview.txt`) |
| `jszip.min.js` | JSZip, a dependency of docx-preview | 3.10.2 | MIT (`LICENSE-jszip.md`) |
| `sais-docx.js` | SAIS glue: sandboxed frame, renderer options, sanitiser | this repo | this repo |

The two libraries are unmodified copies of the files in the npm packages.

To update, install the new version with npm, copy `dist/docx-preview.min.js` and
`dist/jszip.min.js` over these, and run the real-browser check in
`tool/docx_viewer_check/` (`npm install && npm run check`): it renders a normal and
several hostile Word files and fails if anything leaves the page or runs script.
