/*
 * SAIS glue for docx-preview: shows a student's .docx inside a sandboxed
 * iframe, without sending the file anywhere.
 *
 * The file is untrusted. docx-preview is a renderer, not a sanitiser, so:
 *   - it is asked for data: URLs only and no alternative-format chunks;
 *   - the frame has no `allow-scripts` and carries a CSP that forbids every
 *     network load (set by the page that creates the frame, see
 *     lib/utils/web_document_view_web.dart);
 *   - everything it produces is cleaned afterwards (saisSanitize).
 */
(function () {
  'use strict';

  var DROP_TAGS = {
    script: 1, iframe: 1, frame: 1, frameset: 1, object: 1, embed: 1,
    applet: 1, link: 1, meta: 1, base: 1, form: 1, input: 1, button: 1,
    select: 1, textarea: 1, audio: 1, video: 1, source: 1, track: 1,
    portal: 1, template: 1, noscript: 1
  };
  // (foreignObject stays: Word text boxes are drawn with it. Whatever is
  // inside gets the same cleaning as the rest.)
  var DROP_SVG = { use: 1, image: 1, script: 1 };
  var URL_ATTRS = ['src', 'href', 'xlink:href', 'srcset', 'poster', 'action',
    'formaction', 'background', 'data', 'ping', 'cite', 'longdesc', 'usemap'];

  // A style that could make the browser fetch something. Pictures and fonts
  // inside the file arrive as data: URLs and are kept; any other url() goes.
  function cleanCss(text) {
    return String(text)
      .replace(/@import[^;{]*;?/gi, '')
      .replace(/url\(\s*(['"]?)([^)'"]*)\1\s*\)/gi, function (all, quote, target) {
        return /^data:/i.test(target.trim()) ? all : 'none';
      })
      // Anything that still looks like a url() was not a plain one.
      .replace(/url\(\s*(?!['"]?\s*data:)/gi, 'blocked(')
      .replace(/(-webkit-)?image-set\s*\([^)]*\)/gi, 'none')
      .replace(/expression\s*\(/gi, 'blocked(')
      .replace(/-moz-binding\s*:/gi, 'blocked:')
      .replace(/behavior\s*:/gi, 'blocked:');
  }

  function safeLink(value) {
    return /^(https?:|mailto:|#)/i.test(String(value).trim());
  }

  function safeImage(value) {
    return /^data:image\/(png|jpe?g|gif|bmp|webp|svg\+xml|x-emf|x-wmf|emf|wmf);/i
      .test(String(value).trim());
  }

  function cleanElement(el) {
    var tag = el.localName.toLowerCase();
    var inSvg = el.namespaceURI === 'http://www.w3.org/2000/svg';
    if (inSvg ? DROP_SVG[tag] : DROP_TAGS[tag]) {
      el.remove();
      return false;
    }
    var attrs = Array.prototype.slice.call(el.attributes);
    for (var i = 0; i < attrs.length; i++) {
      var name = attrs[i].name.toLowerCase();
      var value = attrs[i].value;
      if (name.indexOf('on') === 0) {
        el.removeAttribute(attrs[i].name);
      } else if (name === 'style') {
        el.setAttribute(attrs[i].name, cleanCss(value));
      } else if (URL_ATTRS.indexOf(name) >= 0) {
        var keep = false;
        if (tag === 'img' && name === 'src') keep = safeImage(value);
        else if (tag === 'a' && name === 'href') keep = safeLink(value);
        else if (inSvg && /href$/.test(name)) keep = value.charAt(0) === '#';
        if (!keep) el.removeAttribute(attrs[i].name);
      }
    }
    if (tag === 'a') {
      el.setAttribute('target', '_blank');
      el.setAttribute('rel', 'noopener noreferrer');
    }
    return true;
  }

  /** Cleans [root] and everything under it, in place. */
  function saisSanitize(root) {
    var all = Array.prototype.slice.call(root.querySelectorAll('*'));
    for (var i = 0; i < all.length; i++) {
      if (all[i].isConnected || root.contains(all[i])) cleanElement(all[i]);
    }
    var styles = root.querySelectorAll('style');
    for (var j = 0; j < styles.length; j++) {
      styles[j].textContent = cleanCss(styles[j].textContent);
    }
  }

  var TOO_LARGE = 'This Word file is too large to preview. Download it instead.';
  var MAX_ENTRIES = 500;
  var MAX_ENTRY_BYTES = 25 * 1024 * 1024;
  var MAX_TOTAL_BYTES = 60 * 1024 * 1024;

  // Inflates one entry only far enough to know it is within [entryCap] and
  // [totalLeft]. The sizes a zip declares can lie, so this counts the bytes
  // that actually come out and stops the moment they pass the cap.
  function measureEntry(file, entryCap, totalLeft) {
    return new Promise(function (resolve, reject) {
      var size = 0;
      var stream = file.internalStream('uint8array');
      stream.on('data', function (chunk) {
        size += chunk.length;
        if (size > entryCap || size > totalLeft) {
          stream.pause();
          reject(new Error(TOO_LARGE));
        }
      });
      stream.on('error', reject);
      stream.on('end', function () { resolve(size); });
      stream.resume();
    });
  }

  async function enforceZipLimits(bytes) {
    var zip = await window.JSZip.loadAsync(bytes);
    var names = Object.keys(zip.files);
    if (names.length > MAX_ENTRIES) {
      throw new Error('This Word file is too complex to preview. Download it instead.');
    }
    var total = 0;
    for (var i = 0; i < names.length; i++) {
      var file = zip.files[names[i]];
      if (file.dir) continue;
      total += await measureEntry(file, MAX_ENTRY_BYTES, MAX_TOTAL_BYTES - total);
    }
  }

  /**
   * Sets up a fresh iframe to show a document: no scripts, and a page whose
   * CSP forbids every network load. Resolves once the frame has loaded.
   */
  function saisConfigureDocxFrame(frame) {
    return new Promise(function (resolve) {
      frame.setAttribute('sandbox',
        'allow-same-origin allow-popups allow-popups-to-escape-sandbox');
      frame.addEventListener('load', function () { resolve(frame); },
        { once: true });
      frame.srcdoc = '<!doctype html><html><head><meta charset="utf-8">' +
        '<meta http-equiv="Content-Security-Policy" content="default-src ' +
        "'none'; img-src data:; font-src data:; style-src 'unsafe-inline'" +
        '"><style>html,body{margin:0;background:#e5e7eb}</style></head>' +
        '<body></body></html>';
    });
  }

  // docx-preview builds its elements in whatever document it is given. In the
  // live page an <img> the file points at nothing (src "null") would start a
  // request at once, before anything could clean it, so the elements are built
  // in an inert document (one with no browsing context never loads anything)
  // and only moved into the frame, whose CSP forbids loads, once cleaned.
  function inertBuilder(inert) {
    function h(elem) {
      if (typeof elem === 'string') return inert.createTextNode(elem);
      if (elem instanceof Node) return elem;
      var tagName = elem.tagName, ns = elem.ns;
      if (tagName === '#fragment') {
        var frag = inert.createDocumentFragment();
        (elem.children || []).forEach(function (c) { frag.appendChild(h(c)); });
        return frag;
      }
      if (tagName === '#comment') {
        return inert.createComment(elem.children ? elem.children[0] : '');
      }
      var el = ns ? inert.createElementNS(ns, tagName) : inert.createElement(tagName);
      if (elem.className) el.setAttribute('class', elem.className);
      if (elem.style) {
        if (typeof elem.style === 'string') el.setAttribute('style', elem.style);
        else Object.assign(el.style, elem.style);
      }
      Object.keys(elem).forEach(function (key) {
        if (['ns', 'tagName', 'className', 'style', 'children'].indexOf(key) >= 0) return;
        if (elem[key] !== undefined) el[key] = elem[key];
      });
      (elem.children || []).forEach(function (c) { el.appendChild(h(c)); });
      return el;
    }
    return h;
  }

  /**
   * Draws [bytes] (a Uint8Array holding a .docx) into [frame], an iframe
   * that has finished loading. Resolves when it is on screen.
   */
  async function saisRenderDocx(bytes, frame) {
    var doc = frame.contentDocument;
    if (!doc || !doc.body) throw new Error('The preview frame is not ready.');
    if (!window.docx || !window.docx.renderAsync) {
      throw new Error('The Word viewer did not load.');
    }
    doc.body.textContent = '';
    await enforceZipLimits(bytes);
    var inert = document.implementation.createHTMLDocument('');
    await window.docx.renderAsync(
      bytes, inert.body, inert.head, {
        h: inertBuilder(inert),
        className: 'docx',
        inWrapper: true,
        ignoreWidth: false,
        ignoreHeight: false,
        ignoreFonts: false,
        breakPages: true,
        renderHeaders: true,
        renderFooters: true,
        renderFootnotes: true,
        renderEndnotes: true,
        renderChanges: false,
        renderComments: false,
        renderAltChunks: false,
        useBase64URL: true,
        experimental: false,
        debug: false
      });
    saisSanitize(inert.body);
    // The renderer's own style sheets live in the head: clean those too.
    var styles = inert.head.querySelectorAll('style');
    for (var i = 0; i < styles.length; i++) {
      styles[i].textContent = cleanCss(styles[i].textContent);
    }
    // Now it can go into the frame, whose CSP is the second line of defence.
    while (inert.head.firstChild) doc.head.appendChild(inert.head.firstChild);
    while (inert.body.firstChild) doc.body.appendChild(inert.body.firstChild);
    // Keys typed inside the frame never reach the app: tell it about Escape,
    // so the viewer can still be closed from the keyboard.
    doc.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') frame.dispatchEvent(new CustomEvent('sais-escape'));
    });
  }

  window.saisConfigureDocxFrame = saisConfigureDocxFrame;
  window.saisSanitize = saisSanitize;
  window.saisRenderDocx = saisRenderDocx;
})();
