/*
 * SAIS class schedule reader: the browser side.
 *
 * window.saisReadSchedule(bytes, mimeType) reads a class schedule picture or
 * PDF on this device and resolves to a JSON string {ok, meetings, warnings,
 * source}; see sais-schedule-layout.js for the meetings. The file itself is
 * never sent anywhere.
 *
 * The reading libraries (Tesseract for pictures, pdf.js for PDFs) are large,
 * so they are fetched from the jsDelivr CDN the first time someone reads a
 * schedule, not from SAIS's own hosting (Firebase's free plan allows only a
 * little download traffic a day). Every file that runs as code is pinned to
 * an exact version and checked against its hash before it runs; see
 * README.md for how to update them.
 */
(function () {
  'use strict';

  const CDN = 'https://cdn.jsdelivr.net/npm/';
  const FILES = {
    tesseract: {
      url: CDN + 'tesseract.js@7.0.0/dist/tesseract.min.js',
      integrity: 'sha384-2BQ3U3OdKOb0Uczxqr41I9UvZkzr4V9Hv8uSzMMZAlmhsFClvdZX5wi5fDCzG+tM',
    },
    tesseractWorker: {
      url: CDN + 'tesseract.js@7.0.0/dist/worker.min.js',
      integrity: 'sha384-iUyp1FxLBc4DYaSwxT1/G6elMdSh3vvQffNSmMiySoXDpk2XfS9ZcM4RjPSiqiw3',
    },
    coreSimd: {
      url: CDN + 'tesseract.js-core@7.0.0/tesseract-core-simd-lstm.wasm.js',
      integrity: 'sha384-1PHRxr8cs/w6IDh6HZYHEHS+Li9cfjahWYKnioD1xvjs7wZD20qpwhD2+ZvhDmHU',
    },
    core: {
      url: CDN + 'tesseract.js-core@7.0.0/tesseract-core-lstm.wasm.js',
      integrity: 'sha384-ljppwjVnA7rpAU/v9enQiR6pXDStaEAYw9I+7ddiEynJcmDNnjHCmcvizBeO3cSA',
    },
    pdf: {
      url: CDN + 'pdfjs-dist@6.5.438/legacy/build/pdf.min.mjs',
      integrity: 'sha384-8Nzt4NtLKsO5Ksqwrdc+JzLh0297H8590bi0lcBPKcMRxReio/DNZsRsiBMZydqe',
    },
    pdfWorker: {
      url: CDN + 'pdfjs-dist@6.5.438/legacy/build/pdf.worker.min.mjs',
      integrity: 'sha384-h2OX4gf3I6e1sZFfB/7wpAKzqaygzUba1e7GWT5x1gZqWrNDRIrSERQHlEFPSfu+',
    },
  };
  // English text data (not code): kept in the browser's storage after the
  // first download.
  const LANG_PATH = CDN + '@tesseract.js-data/eng@1.0.0/4.0.0_best_int';

  // Pictures are read at most this wide; a phone photo is shrunk to it.
  const MAX_WIDTH = 1600;
  const TIME_LIMIT_MS = 90000;

  const blobUrls = new Map();
  let tesseractLoaded = null;
  let pdfLoaded = null;
  let reading = null; // {worker, cancelled}

  function failure(message) {
    const error = new Error(message);
    error.saisMessage = message;
    return error;
  }

  /** A same-origin blob: URL of a CDN file, after checking its hash. */
  async function checkedUrl(file, type) {
    if (blobUrls.has(file.url)) return blobUrls.get(file.url);
    let response;
    try {
      response = await fetch(file.url, { integrity: file.integrity, mode: 'cors', credentials: 'omit' });
    } catch (_) {
      throw failure('The schedule reader could not be downloaded. Check your internet connection and try again.');
    }
    if (!response.ok) {
      throw failure('The schedule reader could not be downloaded. Please try again later.');
    }
    const blob = new Blob([await response.arrayBuffer()], { type });
    const url = URL.createObjectURL(blob);
    blobUrls.set(file.url, url);
    return url;
  }

  function loadTesseract() {
    if (window.Tesseract) return Promise.resolve();
    return (tesseractLoaded ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = FILES.tesseract.url;
      script.integrity = FILES.tesseract.integrity;
      script.crossOrigin = 'anonymous';
      script.onload = () => resolve();
      script.onerror = () => {
        tesseractLoaded = null;
        script.remove();
        reject(failure('The schedule reader could not be downloaded. Check your internet connection and try again.'));
      };
      document.head.append(script);
    }));
  }

  function loadPdf() {
    return (pdfLoaded ??= (async () => {
      const [main, worker] = await Promise.all([
        checkedUrl(FILES.pdf, 'text/javascript'),
        checkedUrl(FILES.pdfWorker, 'text/javascript'),
      ]);
      const pdfjs = await import(main);
      pdfjs.GlobalWorkerOptions.workerSrc = worker;
      return pdfjs;
    })().catch((error) => {
      pdfLoaded = null;
      throw error;
    }));
  }

  /** WebAssembly SIMD, which every current browser has; older ones don't. */
  function hasSimd() {
    try {
      return WebAssembly.validate(new Uint8Array([
        0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10,
        10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11,
      ]));
    } catch (_) {
      return false;
    }
  }

  async function startTesseract() {
    await loadTesseract();
    const [workerPath, corePath] = await Promise.all([
      checkedUrl(FILES.tesseractWorker, 'text/javascript'),
      checkedUrl(hasSimd() ? FILES.coreSimd : FILES.core, 'text/javascript'),
    ]);
    return window.Tesseract.createWorker('eng', 1 /* LSTM only */, {
      workerPath,
      workerBlobURL: false,
      // Tesseract treats a path that doesn't end in "js" as a folder.
      corePath: corePath + '#core.js',
      langPath: LANG_PATH,
      gzip: true,
    });
  }

  function canvasOf(width, height) {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    return canvas;
  }

  function imageOf(canvas) {
    const data = canvas.getContext('2d', { willReadFrequently: true })
      .getImageData(0, 0, canvas.width, canvas.height);
    return { width: canvas.width, height: canvas.height, pixels: data.data };
  }

  async function pictureImage(bytes, type) {
    let bitmap;
    try {
      bitmap = await createImageBitmap(new Blob([bytes], { type }), {
        imageOrientation: 'from-image',
      });
    } catch (_) {
      throw failure('This picture could not be opened. Try a JPG or PNG.');
    }
    const factor = Math.min(1, MAX_WIDTH / bitmap.width);
    const canvas = canvasOf(
      Math.max(1, Math.round(bitmap.width * factor)),
      Math.max(1, Math.round(bitmap.height * factor)),
    );
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    bitmap.close?.();
    return imageOf(canvas);
  }

  /** Page 1 drawn MAX_WIDTH wide, plus its own words when it has a text layer. */
  async function pdfImage(bytes) {
    const pdfjs = await loadPdf();
    // A copy: pdf.js hands the array it is given to its worker, which would
    // empty the caller's (the same bytes are being uploaded meanwhile).
    const task = pdfjs.getDocument({
      data: bytes.slice(),
      isEvalSupported: false,
      enableXfa: false,
      // Data files (not code) for scanned PDFs' images and missing fonts.
      wasmUrl: CDN + 'pdfjs-dist@6.5.438/wasm/',
      standardFontDataUrl: CDN + 'pdfjs-dist@6.5.438/standard_fonts/',
    });
    let doc;
    try {
      doc = await task.promise;
    } catch (_) {
      task.destroy();
      throw failure('This PDF could not be opened.');
    }
    try {
      const page = await doc.getPage(1);
      const base = page.getViewport({ scale: 1 });
      const viewport = page.getViewport({ scale: MAX_WIDTH / base.width });
      const canvas = canvasOf(Math.round(viewport.width), Math.round(viewport.height));
      const context = canvas.getContext('2d', { willReadFrequently: true });
      context.fillStyle = '#ffffff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      await page.render({ canvasContext: context, canvas, viewport }).promise;

      const words = [];
      const content = await page.getTextContent();
      for (const item of content.items) {
        const text = item.str || '';
        if (!text.trim()) continue;
        const tx = pdfjs.Util.transform(viewport.transform, item.transform);
        const height = Math.hypot(tx[2], tx[3]) || 10;
        const width = (item.width || 0) * viewport.scale;
        const left = tx[4];
        const baseline = tx[5];
        // One entry may hold several words: share its width by letters.
        const perChar = text.length ? width / text.length : 0;
        let at = 0;
        for (const part of text.split(/(\s+)/)) {
          if (part.trim()) {
            words.push({
              text: part,
              conf: 100,
              x0: left + at * perChar,
              x1: left + (at + part.length) * perChar,
              y0: baseline - height,
              y1: baseline + height * 0.2,
            });
          }
          at += part.length;
        }
      }
      return { image: imageOf(canvas), words };
    } finally {
      task.destroy();
    }
  }

  function inside(word, rect) {
    const cx = (word.x0 + word.x1) / 2;
    const cy = (word.y0 + word.y1) / 2;
    return cx >= rect.x0 && cx <= rect.x1 && cy >= rect.y0 && cy <= rect.y1;
  }

  async function ocrRead(job, image, rect, options) {
    if (job.cancelled) throw failure('Cancelled.');
    const crop = window.SaisScheduleLayout.cropForOcr(image, rect, options);
    const canvas = canvasOf(crop.width, crop.height);
    canvas.getContext('2d').putImageData(
      new ImageData(new Uint8ClampedArray(crop.pixels), crop.width, crop.height),
      0,
      0,
    );
    await job.worker.setParameters({ tessedit_pageseg_mode: String(options.psm || 6) });
    const { data } = await job.worker.recognize(canvas, {}, { blocks: true });
    const words = [];
    for (const block of data.blocks || []) {
      for (const paragraph of block.paragraphs) {
        for (const line of paragraph.lines) {
          for (const word of line.words) {
            words.push({
              text: word.text,
              conf: word.confidence,
              x0: crop.x0 + word.bbox.x0 / crop.scale,
              y0: crop.y0 + word.bbox.y0 / crop.scale,
              x1: crop.x0 + word.bbox.x1 / crop.scale,
              y1: crop.y0 + word.bbox.y1 / crop.scale,
            });
          }
        }
      }
    }
    if (window.saisScheduleDebug) {
      console.log('read', JSON.stringify(rect), JSON.stringify(options), words.map((w) => w.text + '@' + Math.round(w.x0) + '-' + Math.round(w.x1)).join(' '));
    }
    return words;
  }

  /**
   * The reading itself, given TIME_LIMIT_MS. The first download of the
   * libraries isn't counted: on a slow connection it takes a while, and
   * happens only once.
   */
  function withinTimeLimit(promise) {
    let timer;
    // Once the time is up nobody waits for it: don't report its failure.
    promise.catch(() => {});
    return Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(failure('Reading took too long. Please type your subjects instead.')),
          TIME_LIMIT_MS,
        );
      }),
    ]).finally(() => clearTimeout(timer));
  }

  async function read(bytes, type, job) {
    const layout = window.SaisScheduleLayout;
    if (type === 'application/pdf') {
      const { image, words } = await pdfImage(bytes);
      if (job.cancelled) throw failure('Cancelled.');
      // A PDF made from a spreadsheet carries its words exactly; a scanned
      // one has none, and is read like a picture.
      if (words.length >= 15) {
        const result = await layout.readSchedule(
          image,
          async (_, rect) => words.filter((w) => inside(w, rect)),
          { straighten: false },
        );
        if (result.ok && result.warnings.length === 0) {
          return { ...result, source: 'text' };
        }
      }
      job.worker = await startTesseract();
      const result = await withinTimeLimit(
        layout.readSchedule(image, (picture, rect, options) =>
          ocrRead(job, picture, rect, options),
        ),
      );
      return { ...result, source: 'ocr' };
    }
    const image = await pictureImage(bytes, type);
    job.worker = await startTesseract();
    if (job.cancelled) throw failure('Cancelled.');
    const result = await withinTimeLimit(
      layout.readSchedule(image, (picture, rect, options) =>
        ocrRead(job, picture, rect, options),
      ),
    );
    return { ...result, source: 'ocr' };
  }

  async function recognizeImageText(job, image, psm) {
    const canvas = canvasOf(image.width, image.height);
    canvas.getContext('2d').putImageData(
      new ImageData(new Uint8ClampedArray(image.pixels), image.width, image.height),
      0,
      0,
    );
    await job.worker.setParameters({ tessedit_pageseg_mode: String(psm) });
    const { data } = await job.worker.recognize(canvas);
    return (data && data.text) || '';
  }

  async function readSchoolId(bytes, type, job) {
    const parser = window.SaisIdParser;
    const layout = window.SaisScheduleLayout;
    let image;
    if (type === 'application/pdf') {
      const pdf = await pdfImage(bytes);
      if (job.cancelled) throw failure('Cancelled.');
      if (pdf.words.length >= 5) {
        const parsed = parser.parseSchoolId(pdf.words.map((w) => w.text).join(' '));
        if (parsed.ok) return parsed;
      }
      image = pdf.image;
    } else {
      image = await pictureImage(bytes, type);
    }
    job.worker = await startTesseract();
    if (job.cancelled) throw failure('Cancelled.');
    return withinTimeLimit((async () => {
      const text1 = await recognizeImageText(job, image, 3);
      let combined = text1;
      let parsed = parser.parseSchoolId(combined);
      if (parsed.ok) return parsed;
      if (job.cancelled) throw failure('Cancelled.');

      // Header band: reads "Marinduque State College / University" and
      // campus address even when dark/glossy areas confuse full-page contrast.
      const headerCrop = layout.cropForOcr(
        image,
        {
          x0: 0,
          y0: 0,
          x1: image.width,
          y1: Math.max(1, Math.round(image.height * 0.32)),
        },
        { plain: true, scale: 2 },
      );
      const headerText = await recognizeImageText(job, headerCrop, 6);
      combined = combined + '\n' + headerText;
      parsed = parser.parseSchoolId(combined);
      if (parsed.ok) return parsed;
      if (job.cancelled) throw failure('Cancelled.');

      // Middle band: isolates the Student Number away from photo/footer clutter.
      const midCrop = layout.cropForOcr(
        image,
        {
          x0: 0,
          y0: Math.round(image.height * 0.28),
          x1: image.width,
          y1: Math.max(1, Math.round(image.height * 0.72)),
        },
        { plain: true, scale: 2 },
      );
      const midText = await recognizeImageText(job, midCrop, 6);
      combined = combined + '\n' + midText;
      parsed = parser.parseSchoolId(combined);
      if (parsed.ok) return parsed;
      if (job.cancelled) throw failure('Cancelled.');

      const sparseText = await recognizeImageText(job, image, 11);
      if (job.cancelled) throw failure('Cancelled.');
      const plain = layout.cropForOcr(
        image,
        { x0: 0, y0: 0, x1: image.width, y1: image.height },
        { plain: true },
      );
      const text2 = await recognizeImageText(job, plain, 6);
      combined = combined + '\n' + sparseText + '\n' + text2;
      return parser.parseSchoolId(combined);
    })());
  }

  async function saisReadSchedule(bytes, type) {
    window.saisCancelScheduleRead();
    const job = { worker: null, cancelled: false };
    reading = job;
    try {
      return JSON.stringify(await read(bytes, type, job));
    } catch (error) {
      if (error && error.saisMessage) throw error;
      console.warn('Schedule reader: ' + (error && error.stack ? error.stack : error));
      throw failure('This schedule could not be read. Please type your subjects.');
    } finally {
      // The engine holds 100 MB or more: let it go after every read.
      job.cancelled = true;
      if (job.worker) job.worker.terminate().catch(() => {});
      if (reading === job) reading = null;
    }
  }

  async function saisReadSchoolId(bytes, type) {
    window.saisCancelScheduleRead();
    const job = { worker: null, cancelled: false };
    reading = job;
    try {
      return JSON.stringify(await readSchoolId(bytes, type, job));
    } catch (error) {
      if (error && error.saisMessage) throw error;
      console.warn('School ID reader: ' + (error && error.stack ? error.stack : error));
      throw failure('This school ID could not be read. Upload a clear photo of the front of your MarSU school ID.');
    } finally {
      job.cancelled = true;
      if (job.worker) job.worker.terminate().catch(() => {});
      if (reading === job) reading = null;
    }
  }

  window.saisReadSchedule = saisReadSchedule;
  window.saisReadSchoolId = saisReadSchoolId;
  window.saisCancelScheduleRead = function () {
    if (!reading) return;
    reading.cancelled = true;
    if (reading.worker) reading.worker.terminate().catch(() => {});
    reading = null;
  };
})();
