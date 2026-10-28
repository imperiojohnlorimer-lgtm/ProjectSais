// Real-browser check of the Word viewer glue (web/docx-preview/sais-docx.js).
//
//   cd tool/docx_viewer_check && npm install && npm run check
//
// Needs Chrome or Edge: set CHROME to its path if it is not in a usual place.
// It serves ../../web on a local port, renders a normal .docx and several
// hostile ones in the same kind of frame the app uses, and fails when
//   - the text does not show,
//   - a link, image or style that could reach the network or run code survives,
//   - any request leaves the page while a document is rendered, or
//   - a script in a document runs.
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import JSZip from 'jszip';
import { Document, Packer, Paragraph, Table, TableCell, TableRow, TextRun, ExternalHyperlink } from 'docx';
import puppeteer from 'puppeteer-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(here, '../../web');

const chromePaths = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);
const chrome = chromePaths.find((p) => fs.existsSync(p));
if (!chrome) throw new Error('No Chrome/Edge found: set CHROME.');

// ── a server for the page and a "spy" that must never be called ──
const spyHits = [];
const spy = http.createServer((req, res) => {
  spyHits.push(req.url);
  res.writeHead(200, { 'content-type': 'image/png' });
  res.end();
});
await new Promise((r) => spy.listen(0, '127.0.0.1', r));
const spyPort = spy.address().port;

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/test.html') {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<!doctype html><html><body>
<script src="/docx-preview/jszip.min.js"></script>
<script src="/docx-preview/docx-preview.min.js"></script>
<script src="/docx-preview/sais-docx.js"></script>
</body></html>`);
    return;
  }
  const file = path.join(webRoot, url.pathname);
  if (file.startsWith(webRoot) && fs.existsSync(file) && fs.statSync(file).isFile()) {
    res.writeHead(200, { 'content-type': 'application/javascript' });
    fs.createReadStream(file).pipe(res);
  } else {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

// ── the documents ──
async function normalDocx() {
  const doc = new Document({
    sections: [{
      children: [
        new Paragraph({ children: [new TextRun({ text: 'Juan Dela Cruz', bold: true, size: 32 })] }),
        new Paragraph({
          children: [
            new TextRun('Portfolio: '),
            new ExternalHyperlink({ link: 'https://example.com/juan', children: [new TextRun('example.com/juan')] }),
          ],
        }),
        new Table({
          rows: [new TableRow({ children: [
            new TableCell({ children: [new Paragraph('Skill')] }),
            new TableCell({ children: [new Paragraph('Communication')] }),
          ] })],
        }),
      ],
    }],
  });
  return Packer.toBuffer(doc);
}

/** A normal docx with its document.xml and relationships rewritten. */
async function hostileDocx() {
  const zip = await JSZip.loadAsync(await normalDocx());
  let xml = await zip.file('word/document.xml').async('string');
  // A hyperlink that runs script, and a picture linked from the network.
  xml = xml.replace(
    '</w:body>',
    `<w:p><w:hyperlink r:id="rIdEvil"><w:r><w:t>click me</w:t></w:r></w:hyperlink></w:p>
     <w:p><w:r><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><wp:extent cx="100" cy="100"/>
       <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
       <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="1" name="x"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImg"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="100" cy="100"/></a:xfrm></pic:spPr></pic:pic>
       </a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p></w:body>`,
  );
  zip.file('word/document.xml', xml);
  let rels = await zip.file('word/_rels/document.xml.rels').async('string');
  rels = rels.replace(
    '</Relationships>',
    `<Relationship Id="rIdEvil" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="javascript:window.top.__pwned=1" TargetMode="External"/>
     <Relationship Id="rIdImg" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="http://127.0.0.1:${spyPort}/spy.png" TargetMode="External"/>
     </Relationships>`,
  );
  zip.file('word/_rels/document.xml.rels', rels);
  return zip.generateAsync({ type: 'nodebuffer' });
}

/**
 * A zip whose entry inflates to [bigBytes] but whose headers claim 16 bytes:
 * the sizes a zip declares can lie, so the viewer has to count what comes out.
 */
async function lyingDocx(bigBytes) {
  const zip = await JSZip.loadAsync(await normalDocx());
  zip.file('word/media/padding.bin', Buffer.alloc(bigBytes), { compression: 'DEFLATE' });
  const buf = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  // Patch the declared uncompressed size of that entry in both headers.
  const nameBytes = Buffer.from('word/media/padding.bin');
  let patched = 0;
  for (let i = 0; i < buf.length - 46; i++) {
    const local = buf.readUInt32LE(i) === 0x04034b50;
    const central = buf.readUInt32LE(i) === 0x02014b50;
    if (!local && !central) continue;
    const nameLen = buf.readUInt16LE(i + (local ? 26 : 28));
    const nameAt = i + (local ? 30 : 46);
    if (nameLen === nameBytes.length && buf.subarray(nameAt, nameAt + nameLen).equals(nameBytes)) {
      buf.writeUInt32LE(16, i + (local ? 22 : 24));
      patched++;
    }
  }
  if (patched < 2) throw new Error('could not patch the zip headers');
  return buf;
}

// ── run ──
const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  userDataDir: fs.mkdtempSync(path.join(os.tmpdir(), 'docx-check-')),
  args: ['--no-sandbox'],
});
const failures = [];
const check = (ok, what) => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${what}`);
  if (!ok) failures.push(what);
};

try {
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${port}/test.html`);
  await page.waitForFunction('window.saisRenderDocx && window.docx');

  // Anything the page requests from now on, other than data:/blob:, is a leak.
  const requests = [];
  await page.setRequestInterception(true);
  page.on('request', (r) => {
    const u = r.url();
    if (!u.startsWith('data:') && !u.startsWith('blob:')) requests.push(u);
    r.continue();
  });

  const show = (bytes) =>
    page.evaluate(async (arr) => {
      const frame = document.createElement('iframe');
      document.body.appendChild(frame);
      await window.saisConfigureDocxFrame(frame);
      try {
        await window.saisRenderDocx(new Uint8Array(arr), frame);
      } catch (e) {
        return { error: String(e && e.message || e) };
      }
      const body = frame.contentDocument.body;
      return {
        sandbox: frame.getAttribute('sandbox'),
        text: body.innerText,
        html: body.innerHTML,
        links: Array.from(body.querySelectorAll('a')).map((a) => ({
          href: a.getAttribute('href'),
          rel: a.getAttribute('rel'),
        })),
      };
    }, Array.from(bytes));

  // 1. A normal document.
  const normal = await show(await normalDocx());
  check(!normal.error, 'normal docx renders');
  check(/Juan Dela Cruz/.test(normal.text) && /Communication/.test(normal.text), 'its text and table show');
  check(normal.links.some((l) => l.href === 'https://example.com/juan' && /noopener/.test(l.rel)), 'its https link stays, with noopener');
  check(!/allow-scripts/.test(normal.sandbox), 'the frame is not given allow-scripts');

  // 2. A hostile one.
  const hostile = await show(await hostileDocx());
  check(!hostile.error, 'hostile docx still renders its text' + (hostile.error ? ': ' + hostile.error : ''));
  if (hostile.error) { console.error('hostile docx did not render'); process.exit(1); }
  check(hostile.links.every((l) => !/^javascript:/i.test(l.href || '')), 'no javascript: link survives');
  check(!/<img[^>]+src="http/i.test(hostile.html), 'no network image survives');
  check(await page.evaluate('window.__pwned === undefined'), 'no script ran');
  check(requests.length === 0, `no request left the page while rendering (${requests.join(', ') || 'none'})`);
  check(spyHits.length === 0, 'the spy server was never called');

  // 3. The sanitiser on raw markup, and the frame's CSP on top of it.
  const raw = await page.evaluate(async (spyUrl) => {
    const frame = document.createElement('iframe');
    document.body.appendChild(frame);
    await window.saisConfigureDocxFrame(frame);
    const body = frame.contentDocument.body;
    body.innerHTML = `
      <img id="a" src="${spyUrl}" onerror="parent.__pwned2=1">
      <img id="b" src="data:image/png;base64,iVBORw0KGgo=">
      <a id="c" href="javascript:parent.__pwned3=1">js</a>
      <a id="d" href="https://example.com/x">ok</a>
      <div id="e" style="background:url(${spyUrl});color:red">styled</div>
      <iframe id="f" src="${spyUrl}"></iframe>
      <svg><use href="${spyUrl}"></use><image href="${spyUrl}"/></svg>
      <form action="${spyUrl}"><input name="x"></form>
      <script>parent.__pwned4=1</script>`;
    window.saisSanitize(body);
    await new Promise((r) => setTimeout(r, 300));
    const q = (id) => frame.contentDocument.getElementById(id);
    return {
      a: q('a') && { src: q('a').getAttribute('src'), onerror: q('a').getAttribute('onerror') },
      b: q('b') && q('b').getAttribute('src'),
      c: q('c') && q('c').getAttribute('href'),
      d: q('d') && q('d').getAttribute('href'),
      e: q('e') && q('e').getAttribute('style'),
      f: !!q('f'),
      svgLeft: body.querySelectorAll('use,image').length,
      form: body.querySelectorAll('form,input').length,
      script: body.querySelectorAll('script').length,
      pwned: [window.__pwned2, window.__pwned3, window.__pwned4].some(Boolean),
    };
  }, `http://127.0.0.1:${spyPort}/raw.png`);
  check(raw.a && raw.a.src === null && raw.a.onerror === null, 'http image source and onerror removed');
  check(raw.b && raw.b.startsWith('data:image/png'), 'a data: picture is kept');
  check(raw.c === null, 'javascript: href removed');
  check(raw.d === 'https://example.com/x', 'an https link is kept');
  check(raw.e && !/url\(/i.test(raw.e) && /color:\s*red/.test(raw.e), 'style url() removed, the rest kept');
  check(!raw.f && raw.svgLeft === 0 && raw.form === 0 && raw.script === 0, 'iframe, svg use/image, form, script removed');
  check(!raw.pwned, 'no script ran');
  check(spyHits.length === 0 && requests.length === 0, 'still no request to the spy (the frame CSP blocks loads before cleaning)');

  // 3b. Text boxes (foreignObject), embedded fonts and quoted data: pictures
  // are legitimate and must survive the cleaning.
  const kept = await page.evaluate(async () => {
    const frame = document.createElement('iframe');
    document.body.appendChild(frame);
    await window.saisConfigureDocxFrame(frame);
    const body = frame.contentDocument.body;
    body.innerHTML = `
      <svg id="s"><foreignObject id="fo"><div id="inner" onclick="x()">boxed text</div></foreignObject></svg>
      <div id="q" style='background-image:url("data:image/png;base64,iVBORw0KGgo=")'>q</div>
      <style id="st">@font-face{font-family:F;src:url(data:font/ttf;base64,AAAA)}
        @import url(https://evil.example/x.css);
        .a{background:url(https://evil.example/y.png)} .b{background:image-set("https://evil.example/z.png" 1x)}</style>`;
    window.saisSanitize(body);
    return {
      fo: !!frame.contentDocument.getElementById('fo'),
      inner: frame.contentDocument.getElementById('inner') &&
        frame.contentDocument.getElementById('inner').getAttribute('onclick'),
      quoted: frame.contentDocument.getElementById('q').getAttribute('style'),
      css: frame.contentDocument.getElementById('st').textContent,
    };
  });
  check(kept.fo && kept.inner === null, 'a text box (foreignObject) is kept, cleaned inside');
  check(/url\("data:image\/png/.test(kept.quoted), 'a quoted data: picture in a style is kept');
  check(/url\(data:font\/ttf/.test(kept.css), 'an embedded data: font is kept');
  check(!/evil\.example/.test(kept.css), 'a style sheet loses @import, url() and image-set() that reach out');

  // 3c. The sandbox itself, with the cleaning left out: a script that does
  // get into the frame still cannot run. A frame WITHOUT the sandbox is the
  // control, so this check can fail.
  const sandboxProof = await page.evaluate(async () => {
    async function run(sandboxed) {
      const frame = document.createElement('iframe');
      document.body.appendChild(frame);
      if (sandboxed) await window.saisConfigureDocxFrame(frame);
      else { frame.srcdoc = '<!doctype html><body></body>'; await new Promise((r) => frame.addEventListener('load', r, { once: true })); }
      const key = sandboxed ? '__sandboxed' : '__control';
      const d = frame.contentDocument;
      const s = d.createElement('script');
      s.textContent = 'parent.' + key + '=1';
      d.body.appendChild(s);
      const img = d.createElement('img');
      img.setAttribute('onerror', 'parent.' + key + 'B=1');
      img.src = 'data:image/png;base64,bad';
      d.body.appendChild(img);
      await new Promise((r) => setTimeout(r, 300));
      return { script: window[key] === 1, handler: window[key + 'B'] === 1 };
    }
    return { sandboxed: await run(true), control: await run(false) };
  });
  check(sandboxProof.control.script && sandboxProof.control.handler, 'control: the same payloads DO run in a frame without the sandbox');
  check(!sandboxProof.sandboxed.script && !sandboxProof.sandboxed.handler, 'in the sandboxed frame an inserted script and an inline handler do not run');

  // 3d. A zip that lies about its size must not inflate far.
  const t0 = Date.now();
  const liar = await show(await lyingDocx(90 * 1024 * 1024));
  check(typeof liar.error === 'string' && /too large/i.test(liar.error), 'a zip declaring 16 bytes but inflating 90 MB is refused as too large');
  check(Date.now() - t0 < 20000, `... and it was refused quickly (${Date.now() - t0} ms)`);

  // 4. A file that is not a docx.
  const bad = await show(Buffer.from('this is not a zip'));
  check(typeof bad.error === 'string' && bad.error.length > 0, 'a broken file is refused with a message');
} finally {
  await browser.close();
  server.close();
  spy.close();
}

if (failures.length) {
  console.error(`\n${failures.length} check(s) failed.`);
  process.exit(1);
}
console.log('\nAll checks passed.');
