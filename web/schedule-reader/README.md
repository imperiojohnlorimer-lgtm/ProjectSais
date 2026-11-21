# Class schedule reader

Reads a student's class schedule (MarSU's grid: a Time column of 30-minute
rows, Monday to Saturday, a coloured block per class with the subject, the
instructor and the room or "[Remote]") **on the student's own device**, so
the apply form and the Calendar's "Upload new schedule" can fill in the
subjects. The file is never sent anywhere to be read. Used by
`lib/utils/schedule_reader/schedule_reader_web.dart`; loaded only when someone
reads a schedule.

| File | What |
|---|---|
| `sais-schedule-layout.js` | The layout logic: coloured blocks, tilt, day columns, time scale, the text inside a block. Pure JavaScript, also run by the Node tests. |
| `sais-schedule.js` | Browser side: opens the picture or PDF, downloads and runs the libraries below, exposes `saisReadSchedule(bytes, mimeType)` and `saisCancelScheduleRead()`. |

## Libraries (downloaded from jsDelivr on first use, not hosted here)

Firebase's free hosting plan allows little download traffic a day, and these
are several megabytes, so they come from the jsDelivr CDN. Every file that
runs as code is pinned to an exact version and checked against its SHA-384
hash before it runs (a script tag's `integrity`, or `fetch(..., {integrity})`
then a same-origin blob URL).

| Library | Version | Files | License |
|---|---|---|---|
| tesseract.js | 7.0.0 | `dist/tesseract.min.js`, `dist/worker.min.js` | Apache-2.0 |
| tesseract.js-core | 7.0.0 | `tesseract-core-simd-lstm.wasm.js` (or `tesseract-core-lstm.wasm.js` without WebAssembly SIMD) | Apache-2.0 |
| @tesseract.js-data/eng | 1.0.0 | `4.0.0_best_int/eng.traineddata.gz` (data, not code; kept in the browser's storage after the first download) | MIT |
| pdfjs-dist | 6.5.438 | `legacy/build/pdf.min.mjs`, `legacy/build/pdf.worker.min.mjs` | Apache-2.0 |

A first read downloads about 7 MB (Tesseract and its English data); a PDF
adds about 1.5 MB (pdf.js). A PDF with real text (made from a spreadsheet) is
read from its own words; a picture or a scanned PDF by Tesseract.

## Updating a library

1. `npm install <package>@<version>` in a scratch folder.
2. Compute each file's hash:
   `openssl dgst -sha384 -binary <file> | openssl base64 -A` and put
   `sha384-<hash>` and the new URL in `FILES` in `sais-schedule.js`.
3. Run both checks in `tool/schedule_reader_check/`: `npm test` (layout unit
   tests) and `npm install && npm run check` (reads a made-up schedule as a
   screenshot, a PDF and a tilted, dim "phone photo" in headless Chrome).

## Limits

- Made for the grid above; another layout gives an empty table to type into.
- A tilted photo is straightened; a photo taken at a strong angle
  (perspective) or in poor light may be misread. Doubtful classes are marked
  for the student to check, and the Head compares the list with the picture
  before approving.
- Units are not on the picture: the student types them.
- Browser only. The Android app shows the same table empty, to type into.
