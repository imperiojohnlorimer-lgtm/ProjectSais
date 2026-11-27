/*
 * SAIS MarSU School ID parser.
 *
 * Extracts the Student ID number (2 digits + 1 letter + 4 digits, e.g.
 * 23B0626) from OCR/PDF text and verifies that the document carries MarSU
 * school ID markers while rejecting class schedules, registration forms, and
 * unrelated photos.
 *
 * Runs in the browser (window.SaisIdParser) and in Node for tests
 * (tool/schedule_reader_check/id_parser.test.cjs).
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.SaisIdParser = api;
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const WEEKDAYS = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  ];

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

  function looksLikeScheduleOrCor(text) {
    const lower = text.toLowerCase();
    if (/\b(class\s+schedule|certificate\s+of\s+registration)\b/i.test(lower)) {
      return true;
    }
    let weekdayHits = 0;
    for (const day of WEEKDAYS) {
      if (new RegExp(`\\b${day}\\b`).test(lower)) weekdayHits++;
    }
    return weekdayHits >= 3;
  }

  function fixOcrDigits(raw) {
    return raw.replace(/[Oo]/g, '0').replace(/[Il|]/g, '1');
  }

  const OCR_CAMPUS_MAP = { '8': 'B', '5': 'S', '6': 'G', '7': 'T' };

  function extractStudentId(text, options) {
    const exact = /\b(\d{2}[A-Za-z]\d{4})\b/g;
    for (const m of text.matchAll(exact)) {
      return m[1].toUpperCase();
    }
    const fuzzy = /\b([0-9OoIl|]{2})([A-Za-z])([0-9OoIl|]{4})\b/g;
    for (const m of text.matchAll(fuzzy)) {
      const candidate =
        fixOcrDigits(m[1]) + m[2].toUpperCase() + fixOcrDigits(m[3]);
      if (/^\d{2}[A-Z]\d{4}$/.test(candidate)) return candidate;
    }
    if (options && options.allowOcrCampusDigit) {
      const campusLookalike = /\b([0-9OoIl|]{2})([8567])([0-9OoIl|]{4})\b/g;
      for (const m of text.matchAll(campusLookalike)) {
        const yy = fixOcrDigits(m[1]);
        const seq = fixOcrDigits(m[3]);
        const yearNum = Number(yy);
        if (
          /^\d{2}$/.test(yy) &&
          yearNum >= 15 &&
          yearNum <= 28 &&
          /^\d{4}$/.test(seq)
        ) {
          return yy + OCR_CAMPUS_MAP[m[2]] + seq;
        }
      }
    }
    return null;
  }

  function looksLikeMarsuSchool(text) {
    if (/\b(marinduque|marsu|msc|state\s+universit\w*|state\s+colleg\w*|manguera)\b/i.test(text)) {
      return true;
    }
    if (/\btanza\b/i.test(text) && /\bbo[o0]?ac\b/i.test(text)) {
      return true;
    }
    const words = text.toLowerCase().replace(/[^a-z\s]/g, ' ').split(/\s+/);
    for (const w of words) {
      if (w.length >= 8 && w.length <= 12 && editDistance(w, 'marinduque') <= 2) {
        return true;
      }
    }
    return false;
  }

  /**
   * Parses [text] from a school ID photo or PDF.
   * Returns `{ ok, studentId, reason }`.
   */
  function parseSchoolId(text) {
    const raw = String(text || '');
    if (looksLikeScheduleOrCor(raw)) {
      return {
        ok: false,
        studentId: null,
        reason:
          'This looks like a class schedule or registration form, not a school ID. Upload a clear photo of the front of your MarSU school ID.',
      };
    }
    const isMarsu = looksLikeMarsuSchool(raw);
    const studentId = extractStudentId(raw, { allowOcrCampusDigit: isMarsu });
    if (!studentId) {
      return {
        ok: false,
        studentId: null,
        reason:
          'No MarSU Student ID number was found. Upload a clear photo of the front of your school ID.',
      };
    }
    if (!isMarsu) {
      return {
        ok: false,
        studentId: null,
        reason:
          'This does not look like a MarSU school ID. Upload a clear photo of the front of your MarSU school ID.',
      };
    }
    return { ok: true, studentId, reason: null };
  }

  return {
    parseSchoolId,
    extractStudentId,
    looksLikeMarsuSchool,
    looksLikeScheduleOrCor,
  };
});
