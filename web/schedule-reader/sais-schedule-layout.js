/*
 * SAIS class schedule reader: the layout logic.
 *
 * Reads MarSU's class schedule grid (a Time column of 30-minute rows,
 * Monday to Saturday columns, a coloured block per class holding the
 * subject, the instructor and the room or "[Remote]") from a picture's
 * pixels plus the words found in parts of it. It knows nothing about where
 * the words come from: `sais-schedule.js` passes either Tesseract (pictures,
 * scanned PDFs) or a PDF's own text layer.
 *
 * Runs in the browser (window.SaisScheduleLayout) and in Node for the tests
 * (tool/schedule_reader_check/layout.test.cjs). Nothing here leaves the
 * device.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.SaisScheduleLayout = api;
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const DAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

  // ── Coloured blocks ──────────────────────────────────────────────────

  /** True for a strongly coloured pixel: not white, grey, black or a shadow. */
  function isColoured(r, g, b) {
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    if (max < 110) return false; // dark: text, grid lines, deep shadow
    return (max - min) / max > 0.3;
  }

  /**
   * The coloured rectangles of a picture: one per class block. Connected
   * areas of coloured pixels, kept when big enough and mostly filled (text
   * inside a block leaves holes, a stray coloured logo is usually small).
   * Back-to-back classes are split by the dark border line between them.
   */
  function findBlocks(image) {
    const { width, height, pixels } = image;
    const n = width * height;
    const mask = new Uint8Array(n);
    for (let i = 0, p = 0; i < n; i++, p += 4) {
      if (isColoured(pixels[p], pixels[p + 1], pixels[p + 2])) mask[i] = 1;
    }
    const label = new Int32Array(n);
    const stack = new Int32Array(n);
    const blocks = [];
    let next = 0;
    for (let start = 0; start < n; start++) {
      if (!mask[start] || label[start]) continue;
      next++;
      let top = 0;
      stack[top++] = start;
      label[start] = next;
      let x0 = width, y0 = height, x1 = 0, y1 = 0, count = 0;
      while (top > 0) {
        const i = stack[--top];
        const x = i % width;
        const y = (i - x) / width;
        count++;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        if (x > 0 && mask[i - 1] && !label[i - 1]) { label[i - 1] = next; stack[top++] = i - 1; }
        if (x < width - 1 && mask[i + 1] && !label[i + 1]) { label[i + 1] = next; stack[top++] = i + 1; }
        if (y > 0 && mask[i - width] && !label[i - width]) { label[i - width] = next; stack[top++] = i - width; }
        if (y < height - 1 && mask[i + width] && !label[i + width]) { label[i + width] = next; stack[top++] = i + width; }
      }
      const w = x1 - x0 + 1;
      const h = y1 - y0 + 1;
      if (w < width * 0.04 || h < height * 0.02) continue;
      if (w > width * 0.5) continue; // a banner or title bar, not a class
      if (count / (w * h) < 0.55) continue;
      blocks.push({ x0, y0, x1: x1 + 1, y1: y1 + 1, fill: count / (w * h) });
    }
    blocks.sort((a, b) => a.x0 - b.x0 || a.y0 - b.y0);
    return blocks;
  }

  /**
   * How far the picture leans, from the top and bottom edges of its
   * blocks: the change in y per pixel to the right (0 when straight). The
   * middle value across the blocks, so one odd block doesn't decide it.
   */
  function estimateTilt(image, blocks) {
    const { width, pixels } = image;
    const coloured = (x, y) => {
      const p = (y * width + x) * 4;
      return isColoured(pixels[p], pixels[p + 1], pixels[p + 2]);
    };
    const slopes = [];
    for (const block of blocks) {
      const w = block.x1 - block.x0;
      if (w < 20) continue;
      for (const fromTop of [true, false]) {
        const points = [];
        for (let x = Math.round(block.x0 + w * 0.15); x < block.x1 - w * 0.15; x++) {
          if (fromTop) {
            for (let y = block.y0; y < block.y1; y++) {
              if (coloured(x, y)) {
                points.push([x, y]);
                break;
              }
            }
          } else {
            for (let y = block.y1 - 1; y >= block.y0; y--) {
              if (coloured(x, y)) {
                points.push([x, y]);
                break;
              }
            }
          }
        }
        if (points.length < 10) continue;
        const n = points.length;
        const mx = points.reduce((s, [x]) => s + x, 0) / n;
        const my = points.reduce((s, [, y]) => s + y, 0) / n;
        let num = 0;
        let den = 0;
        for (const [x, y] of points) {
          num += (x - mx) * (y - my);
          den += (x - mx) * (x - mx);
        }
        if (den > 0) slopes.push(num / den);
      }
    }
    if (slopes.length === 0) return 0;
    slopes.sort((a, b) => a - b);
    const middle = slopes[Math.floor(slopes.length / 2)];
    return Math.max(-0.2, Math.min(0.2, middle));
  }

  // ── Day columns ──────────────────────────────────────────────────────

  function letters(text) {
    return String(text || '').toLowerCase().replace(/[^a-z]/g, '');
  }

  function editDistance(a, b) {
    const dp = [];
    for (let i = 0; i <= a.length; i++) dp.push([i]);
    for (let j = 1; j <= b.length; j++) dp[0][j] = j;
    for (let i = 1; i <= a.length; i++) {
      for (let j = 1; j <= b.length; j++) {
        dp[i][j] = Math.min(
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
        );
      }
    }
    return dp[a.length][b.length];
  }

  /** 0 (Monday) .. 5 (Saturday) for a word that reads like a day, else -1. */
  function dayIndex(text) {
    const word = letters(text);
    if (word.length < 3) return -1;
    let best = -1;
    let bestDistance = 99;
    for (let d = 0; d < DAYS.length; d++) {
      const day = DAYS[d];
      const distance = word.length <= 4
        ? (day.startsWith(word) ? 0 : 99) // "Mon", "Tues", "Thur"
        : editDistance(word, day);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = d;
      }
    }
    return bestDistance <= 2 ? best : -1;
  }

  /**
   * The centre x of each day's column, Monday first, from the header words.
   * Days the reader missed are filled in from the spacing of those it found.
   * Null when fewer than two days were found.
   */
  function dayCentres(words) {
    const found = new Map();
    for (const w of words) {
      const d = dayIndex(w.text);
      if (d < 0 || found.has(d)) continue;
      found.set(d, (w.x0 + w.x1) / 2);
    }
    if (found.size < 2) return null;
    // Columns are evenly spaced: centre = a + b * dayIndex. A misread word
    // can sit off its column (say "Tuesday" read together with a lost
    // "Monday"), so the line is the one most days agree with: tried through
    // every pair of days, kept with the days within a fifth of a column of
    // it, then fitted to those. With three or more such days every centre
    // comes from the line.
    const fit = (pts) => {
      const n = pts.length;
      const sx = pts.reduce((s, [d]) => s + d, 0);
      const sy = pts.reduce((s, [, x]) => s + x, 0);
      const sxx = pts.reduce((s, [d]) => s + d * d, 0);
      const sxy = pts.reduce((s, [d, x]) => s + d * x, 0);
      const b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
      return { a: (sy - b * sx) / n, b };
    };
    const all = [...found.entries()];
    let pts = all;
    if (all.length >= 3) {
      let best = null;
      for (let i = 0; i < all.length; i++) {
        for (let j = i + 1; j < all.length; j++) {
          const bb = (all[j][1] - all[i][1]) / (all[j][0] - all[i][0]);
          if (!(bb > 0)) continue;
          const aa = all[i][1] - bb * all[i][0];
          const agree = all.filter(([d, x]) => Math.abs(aa + bb * d - x) <= bb * 0.2);
          if (!best || agree.length > best.length) best = agree;
        }
      }
      if (best && best.length >= 2) pts = best;
    }
    let { a, b } = fit(pts);
    if (!(b > 0)) return null;
    const centres = [];
    for (let d = 0; d < DAYS.length; d++) {
      centres.push(pts.length >= 3 ? a + b * d : found.has(d) ? found.get(d) : a + b * d);
    }
    const headerTop = Math.min(
      ...words.filter((w) => dayIndex(w.text) >= 0).map((w) => w.y0),
    );
    return { centres, spacing: b, headerTop };
  }

  /** The day (0..5) whose column holds x, or -1 when x is outside them all. */
  function dayAt(x, days) {
    let best = -1;
    let bestGap = Infinity;
    days.centres.forEach((c, d) => {
      const gap = Math.abs(c - x);
      if (gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    });
    return bestGap <= days.spacing * 0.6 ? best : -1;
  }

  // ── Time scale ───────────────────────────────────────────────────────

  /** "7:30", "12.30", "1000" (a lost colon) -> {h, m}; else null. */
  function parseClock(text) {
    const t = String(text || '').trim().replace(/[oO]/g, '0').replace(/[lI|]/g, '1');
    let m = /^(\d{1,2})\s*[:.;,]\s*(\d{2})$/.exec(t);
    if (!m) m = /^(\d{1,2})(\d{2})$/.exec(t);
    if (!m) return null;
    const h = Number(m[1]);
    const min = Number(m[2]);
    if (h < 1 || h > 12 || (min !== 0 && min !== 30)) return null;
    return { h, m: min };
  }

  /**
   * Minutes after midnight for the time labels, top to bottom. A schedule
   * runs from morning to evening, so the first label is AM unless it reads
   * 12 or 1-6, and each later one is the first time after the one above.
   */
  function labelMinutes(labels) {
    const sorted = [...labels].sort((a, b) => a.y - b.y);
    const out = [];
    let previous = -1;
    for (const label of sorted) {
      const base = (label.h % 12) * 60 + label.m;
      let minutes;
      if (previous < 0) {
        minutes = label.h === 12 || label.h <= 6 ? base + 720 : base;
      } else {
        minutes = base >= previous ? base : base + 720;
        if (minutes < previous) continue;
      }
      out.push({ y: label.y, minutes });
      previous = minutes;
    }
    return out;
  }

  /**
   * y = a + b * minutes, fitted to the time labels and robust to a few
   * misread ones: the pair of labels most others agree with sets the line,
   * then every label that agrees refines it. Null with too few labels.
   */
  function fitTimeScale(words) {
    const labels = [];
    for (const w of words) {
      const clock = parseClock(w.text);
      if (clock) labels.push({ ...clock, y: (w.y0 + w.y1) / 2 });
    }
    const points = labelMinutes(labels);
    if (points.length < 3) return null;
    let best = null;
    for (let i = 0; i < points.length; i++) {
      for (let j = i + 1; j < points.length; j++) {
        const p = points[i];
        const q = points[j];
        if (q.minutes === p.minutes) continue;
        const b = (q.y - p.y) / (q.minutes - p.minutes);
        if (!(b > 0)) continue;
        const a = p.y - b * p.minutes;
        const tolerance = b * 30 * 0.35;
        const inliers = points.filter((r) => Math.abs(a + b * r.minutes - r.y) <= tolerance);
        if (!best || inliers.length > best.length) best = inliers;
      }
    }
    if (!best || best.length < 3) return null;
    const n = best.length;
    const sx = best.reduce((s, r) => s + r.minutes, 0);
    const sy = best.reduce((s, r) => s + r.y, 0);
    const sxx = best.reduce((s, r) => s + r.minutes * r.minutes, 0);
    const sxy = best.reduce((s, r) => s + r.minutes * r.y, 0);
    const b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
    const a = (sy - b * sx) / n;
    if (!(b > 0)) return null;
    return { a, b, labels: n };
  }

  /** The time at y, rounded to the nearest half hour. */
  function minutesAt(y, scale) {
    return Math.round((y - scale.a) / scale.b / 30) * 30;
  }

  // ── Text inside a block ──────────────────────────────────────────────

  /** Words grouped into lines, top to bottom, each line left to right. */
  function toLines(words) {
    const sorted = [...words]
      .filter((w) => String(w.text || '').trim() !== '')
      .sort((a, b) => (a.y0 + a.y1) / 2 - (b.y0 + b.y1) / 2);
    const lines = [];
    for (const w of sorted) {
      const mid = (w.y0 + w.y1) / 2;
      const line = lines.find((l) => Math.abs(l.mid - mid) <= Math.max(4, (w.y1 - w.y0) * 0.6));
      if (line) {
        line.words.push(w);
      } else {
        lines.push({ mid, words: [w] });
      }
    }
    lines.sort((a, b) => a.mid - b.mid);
    return lines.map((l) => {
      l.words.sort((a, b) => a.x0 - b.x0);
      return {
        text: l.words.map((w) => String(w.text).trim()).join(' ').replace(/\s+/g, ' ').trim(),
        conf: l.words.reduce((s, w) => s + (w.conf == null ? 100 : w.conf), 0) / l.words.length,
      };
    });
  }

  const REMOTE = /\b(remote|online|virtual|async(hronous)?)\b/i;

  function looksLikeName(text) {
    // "J Mercene", "RC Perez", "K. Omiping", "E. De Luna-Malinao", "A. MAgcamit"
    return /^[A-Z]{1,3}\.?\s+[A-Za-z][A-Za-z.'-]*(\s+[A-Za-z][A-Za-z.'-]*){0,3}$/.test(text.trim());
  }

  /**
   * A room code with the usual misreads of its number put right: "CLS" is
   * CL5, "CLO" CL0, "Rm l2" Rm 12. Only letters that come after a room
   * prefix are touched.
   */
  function fixRoom(text) {
    const m = /^(CL|LAB|RM|ROOM)(\s?-?\s?)([0-9SOIlZB]{1,4})$/i.exec(text.trim());
    if (!m) return text;
    const digits = m[3].replace(/[SOIlZB]/g, (c) => ({ S: '5', O: '0', I: '1', l: '1', Z: '2', B: '8' })[c]);
    return m[1] + m[2] + digits;
  }

  function looksLikeRoom(text) {
    return /\b(cl|lab|room|rm|bldg|building|hall|gym|court|avr|library)\b|^[A-Z]{1,4}\s?-?\d{1,4}[A-Z]?$/i.test(text.trim());
  }

  function tidy(text) {
    return text
      .replace(/^[\s|\[\](){}'"`~_—–-]+|[\s|\[\](){}'"`~_—–-]+$/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  }

  /**
   * Subject, instructor, room and mode from a block's lines. The last line
   * is the room, or "[Remote]" for an online class; the one above it the
   * instructor; everything above that the subject (it often wraps).
   */
  function parseBlockText(lines) {
    const kept = lines
      .map((l) => ({ text: tidy(l.text), conf: l.conf }))
      .filter((l) => (l.text.match(/[A-Za-z0-9]/g) || []).length >= 2);
    const result = { title: '', instructor: '', room: '', mode: 'Face-to-Face', conf: 0 };
    if (kept.length === 0) return result;
    result.conf = Math.min(...kept.map((l) => l.conf));
    const rest = [...kept];
    const last = rest[rest.length - 1];
    if (rest.length >= 2 && REMOTE.test(last.text)) {
      result.mode = 'Online';
      rest.pop();
    } else if (rest.length >= 3 || (rest.length === 2 && looksLikeRoom(last.text) && !looksLikeName(last.text))) {
      result.room = fixRoom(last.text);
      rest.pop();
    }
    if (rest.length >= 2 && looksLikeName(rest[rest.length - 1].text)) {
      result.instructor = rest.pop().text;
    } else if (rest.length >= 3) {
      result.instructor = rest.pop().text;
    }
    result.title = rest.map((l) => l.text).join(' ').replace(/\s+([:,])/g, '$1').trim();
    return result;
  }

  // ── Pictures for the text reader ─────────────────────────────────────

  /**
   * The part `rect` of the picture for the text reader, as {width, height,
   * pixels (RGBA), x0, y0, scale}. Options:
   * - `scale`: enlarge it (small print reads better larger);
   * - `plain`: grey levels only, the background stretched to white (print
   *   on a yellow or green block, or on a dim photo, reads better so);
   * - `clearLines`: then paint long straight dark runs (the grid's lines)
   *   white, since Tesseract reads the Time column's labels poorly between
   *   them; letters never make runs that long;
   * - `angle`: turn it this many radians (clockwise) about its centre, to
   *   straighten a tilted photo.
   */
  function cropForOcr(image, rect, options) {
    const { scale = 1, clearLines = false, plain = false, angle = 0 } = options || {};
    const rx0 = Math.max(0, Math.floor(rect.x0));
    const ry0 = Math.max(0, Math.floor(rect.y0));
    const rw = Math.max(1, Math.min(image.width, Math.ceil(rect.x1)) - rx0);
    const rh = Math.max(1, Math.min(image.height, Math.ceil(rect.y1)) - ry0);
    // Turning needs the picture just outside the part too.
    const margin = angle ? Math.ceil(Math.abs(Math.sin(angle)) * Math.max(rw, rh) / 2) + 2 : 0;
    const x0 = Math.max(0, rx0 - margin);
    const y0 = Math.max(0, ry0 - margin);
    const w = Math.min(image.width, rx0 + rw + margin) - x0;
    const h = Math.min(image.height, ry0 + rh + margin) - y0;
    const src = new Uint8ClampedArray(w * h * 4);
    for (let y = 0; y < h; y++) {
      const from = ((y0 + y) * image.width + x0) * 4;
      src.set(image.pixels.subarray(from, from + w * 4), y * w * 4);
    }
    if (plain) {
      // Grey levels, stretched so the block's colour becomes white: on a
      // mid-grey background (green turns about 120) Tesseract may take the
      // text for light-on-dark and read nothing.
      const grey = new Uint8Array(w * h);
      const histogram = new Uint32Array(256);
      for (let i = 0; i < w * h; i++) {
        const p = i * 4;
        const v = Math.round(src[p] * 0.299 + src[p + 1] * 0.587 + src[p + 2] * 0.114);
        grey[i] = v;
        histogram[v]++;
      }
      const level = (share) => {
        let seen = 0;
        for (let v = 0; v < 256; v++) {
          seen += histogram[v];
          if (seen >= share * w * h) return v;
        }
        return 255;
      };
      // Light print on a dark cell (a maroon header, say) is turned round
      // first: Tesseract reads dark print on light.
      // Light print is told by the pixels far from the cell's own shade:
      // mostly lighter ones means white text (a green cell with black text,
      // dark as it may be, has mostly darker ones).
      const cell = level(0.6);
      let lighter = 0;
      let darker = 0;
      for (let i = 0; i < w * h; i++) {
        if (grey[i] > cell + 60) lighter++;
        else if (grey[i] < cell - 60) darker++;
      }
      if (lighter > darker) {
        histogram.fill(0);
        for (let i = 0; i < w * h; i++) {
          grey[i] = 255 - grey[i];
          histogram[grey[i]]++;
        }
      }
      const low = level(0.02);
      const background = Math.max(low + 1, level(0.6));
      for (let i = 0; i < w * h; i++) {
        const v = Math.max(0, Math.min(255, ((grey[i] - low) * 255) / (background - low)));
        src[i * 4] = src[i * 4 + 1] = src[i * 4 + 2] = v;
      }
    }
    if (clearLines) {
      const dark = (i) => src[i] * 0.299 + src[i + 1] * 0.587 + src[i + 2] * 0.114 < 150;
      const white = new Uint8Array(w * h);
      const minRunX = Math.max(25, Math.round(image.width * 0.035));
      const minRunY = Math.max(25, Math.round(image.height * 0.05));
      for (let y = 0; y < h; y++) {
        let run = 0;
        for (let x = 0; x <= w; x++) {
          if (x < w && dark((y * w + x) * 4)) {
            run++;
          } else {
            if (run >= minRunX) for (let k = x - run; k < x; k++) white[y * w + k] = 1;
            run = 0;
          }
        }
      }
      for (let x = 0; x < w; x++) {
        let run = 0;
        for (let y = 0; y <= h; y++) {
          if (y < h && dark((y * w + x) * 4)) {
            run++;
          } else {
            if (run >= minRunY) for (let k = y - run; k < y; k++) white[k * w + x] = 1;
            run = 0;
          }
        }
      }
      for (let i = 0; i < w * h; i++) {
        if (white[i]) src.fill(255, i * 4, i * 4 + 3);
      }
    }
    const W = Math.max(1, Math.round(rw * scale));
    const H = Math.max(1, Math.round(rh * scale));
    const out = new Uint8ClampedArray(W * H * 4);
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    // The part's centre, in `src`.
    const cx = rx0 - x0 + rw / 2;
    const cy = ry0 - y0 + rh / 2;
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const du = x / scale - rw / 2;
        const dv = y / scale - rh / 2;
        const sx = cx + cos * du - sin * dv;
        const sy = cy + sin * du + cos * dv;
        const o = (y * W + x) * 4;
        if (sx < 0 || sy < 0 || sx > w - 1 || sy > h - 1) {
          out.fill(255, o, o + 4);
          continue;
        }
        const fx = Math.floor(sx);
        const fy = Math.floor(sy);
        const fx1 = Math.min(w - 1, fx + 1);
        const fy1 = Math.min(h - 1, fy + 1);
        const ax = sx - fx;
        const ay = sy - fy;
        for (let c = 0; c < 4; c++) {
          const a = src[(fy * w + fx) * 4 + c];
          const b = src[(fy * w + fx1) * 4 + c];
          const cc = src[(fy1 * w + fx) * 4 + c];
          const d = src[(fy1 * w + fx1) * 4 + c];
          out[o + c] = (a * (1 - ax) + b * ax) * (1 - ay) + (cc * (1 - ax) + d * ax) * ay;
        }
      }
    }
    return { width: W, height: H, pixels: out, x0: rx0, y0: ry0, scale };
  }

  // ── Putting it together ──────────────────────────────────────────────

  function inside(word, rect) {
    const cx = (word.x0 + word.x1) / 2;
    const cy = (word.y0 + word.y1) / 2;
    return cx >= rect.x0 && cx <= rect.x1 && cy >= rect.y0 && cy <= rect.y1;
  }

  /** Lowercase letters and digits only, for matching a subject across days. */
  function subjectKey(title) {
    return String(title || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  }

  /**
   * How much to enlarge a part before reading it: `atWidth960` times for a
   * picture 960 pixels wide (a typical screenshot of the grid), less for a
   * bigger one, between 1 and 4.
   */
  function ocrScale(image, atWidth960) {
    return Math.min(4, Math.max(1, (atWidth960 * 960) / image.width));
  }

  /**
   * Reads a schedule. `read(picture, rect, options)` resolves to the words
   * found in that part of `picture` (the one given here, or its
   * straightened copy); words carry {text, conf, x0, y0, x1, y1} in picture
   * coordinates. Options: `psm` (Tesseract's page segmentation: 6 for one
   * block of text, 11 for scattered words), `scale`, `clearLines` and
   * `plain`, which an OCR reader passes on to [cropForOcr]; a PDF's text
   * layer ignores them. Pass `{straighten: false}` for a PDF's text layer,
   * whose words can't follow a turned picture.
   *
   * Resolves to {ok, meetings, warnings}. Each meeting: {title, instructor,
   * room, mode, weekday (1 = Monday .. 6 = Saturday), start, end (minutes
   * after midnight, or null when unknown), check (true when it should be
   * looked at), conf}.
   */
  async function readSchedule(image, read, options) {
    const { straighten = true } = options || {};
    const warnings = [];
    let blocks = findBlocks(image);
    // A tilted photo is straightened first (more than about a third of a
    // degree), so the rest reads it like a screenshot.
    if (straighten) {
      const tilt = estimateTilt(image, blocks);
      if (Math.abs(tilt) > 0.006) {
        image = cropForOcr(
          image,
          { x0: 0, y0: 0, x1: image.width, y1: image.height },
          { angle: Math.atan(tilt) },
        );
        blocks = findBlocks(image);
      }
    }
    if (blocks.length === 0) {
      return { ok: false, meetings: [], warnings: ['No class blocks were found.'] };
    }
    const top = Math.min(...blocks.map((b) => b.y0));
    const left = Math.min(...blocks.map((b) => b.x0));

    // The header row sits above the first block.
    const headerWords = await read(
      image,
      { x0: 0, y0: 0, x1: image.width, y1: Math.min(image.height, top + image.height * 0.03) },
      { psm: 11, plain: true, clearLines: true },
    );
    let days = dayCentres(headerWords);
    if (!days && top > 2) {
      // Coloured header cells count as blocks, so "above the first block"
      // can miss the day names: try the top quarter.
      days = dayCentres(
        await read(
          image,
          { x0: 0, y0: 0, x1: image.width, y1: Math.round(image.height * 0.25) },
          { psm: 11, plain: true, clearLines: true },
        ),
      );
    }
    if (!days) warnings.push('The day names could not be read.');

    // The time labels sit left of the first day column.
    const timeRight = days
      ? Math.max(1, Math.round(days.centres[0] - days.spacing * 0.5))
      : Math.max(1, left);
    const timeTop = days ? Math.round(days.headerTop) : 0;
    const timeWords = await read(
      image,
      { x0: 0, y0: timeTop, x1: timeRight, y1: image.height },
      { psm: 11, scale: ocrScale(image, 2), plain: true, clearLines: true },
    );
    const scale = fitTimeScale(timeWords);
    if (!scale) warnings.push('The times could not be read.');

    const meetings = [];
    for (const block of blocks) {
      if (days && block.x1 <= timeRight) continue; // inside the Time column
      const pad = 2;
      const rect = {
        x0: block.x0 + pad,
        y0: block.y0 + pad,
        x1: block.x1 - pad,
        y1: block.y1 - pad,
      };
      const words = (
        await read(image, rect, { psm: 6, scale: ocrScale(image, 3), plain: true })
      ).filter((w) => inside(w, rect));
      const text = parseBlockText(toLines(words));
      // A coloured header cell ("Monday", "Time") is not a class.
      if (/^time$/i.test(letters(text.title)) || (text.title.split(/\s+/).length === 1 && dayIndex(text.title) >= 0)) {
        continue;
      }
      const dayOfBlock = days ? dayAt((block.x0 + block.x1) / 2, days) : -1;
      let start = scale ? minutesAt(block.y0, scale) : null;
      let end = scale ? minutesAt(block.y1, scale) : null;
      const check =
        !text.title ||
        text.conf < 70 ||
        dayOfBlock < 0 ||
        start == null ||
        end == null ||
        end <= start ||
        start < 6 * 60 ||
        end > 21 * 60;
      if (start != null && end != null && (end <= start || start < 0)) {
        start = null;
        end = null;
      }
      meetings.push({
        title: text.title,
        instructor: text.instructor,
        room: text.room,
        mode: text.mode,
        weekday: dayOfBlock >= 0 ? dayOfBlock + 1 : null,
        start,
        end,
        check,
        conf: Math.round(text.conf),
      });
    }

    // One spelling per subject. Readings of one subject on different days
    // that differ by a letter or two ("Data Min", "Data Mini") are taken as
    // the same subject: the clearest reading is used for all of them, and
    // since one of them was misread, all are marked to be checked.
    const groups = [];
    for (const m of meetings) {
      const key = subjectKey(m.title);
      if (!key) continue;
      const group = groups.find((g) => {
        const other = subjectKey(g[0].title);
        return editDistance(key, other) <= Math.max(1, Math.floor(Math.min(key.length, other.length) * 0.15));
      });
      if (group) group.push(m);
      else groups.push([m]);
    }
    for (const group of groups) {
      const best = group.reduce((x, y) => (y.conf > x.conf ? y : x));
      const differ = group.some((m) => subjectKey(m.title) !== subjectKey(best.title));
      for (const m of group) {
        m.title = best.title;
        if (differ) m.check = true;
      }
    }

    meetings.sort(
      (a, b) =>
        (a.weekday || 9) - (b.weekday || 9) || (a.start ?? 9999) - (b.start ?? 9999),
    );
    return { ok: meetings.length > 0, meetings, warnings };
  }

  return {
    findBlocks,
    dayIndex,
    dayCentres,
    dayAt,
    parseClock,
    labelMinutes,
    fitTimeScale,
    minutesAt,
    toLines,
    parseBlockText,
    fixRoom,
    subjectKey,
    cropForOcr,
    estimateTilt,
    readSchedule,
  };
});
