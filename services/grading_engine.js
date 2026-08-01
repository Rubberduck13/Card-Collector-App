// Defensive require: if `sharp` is not installed the grading engine will not crash.
// Instead we return a safe fallback report from gradeBuffer.
let sharp = null;
try {
  sharp = require('sharp');
} catch (e) {
  // Do not throw. Log and allow the rest of the module to load.
  // The gradeBuffer function checks for `sharp` and returns a defensive report when it's missing.
  // This keeps the service up even in environments where native deps aren't available.
  // eslint-disable-next-line no-console
  console.warn('services/grading_engine: optional dependency `sharp` not available — grading will return fallback reports.');
}

/**
 * services/grading_engine.js
 *
 * Phase 1 grading engine skeleton using `sharp` for image preprocessing and fast pixel access.
 * This module exposes a single async function `gradeBuffer(buffer, options)` which accepts an
 * image Buffer (e.g. from multer memory storage: `req.file.buffer`) and returns a grading report
 * JSON object with the following shape (Phase 1 API Output Format expected):
 *
 * {
 *  centering: number (0-100),
 *  corners: number (0-100),
 *  edges: number (0-100),
 *  surface: number (0-100),
 *  weighted: number (0-100),
 *  label: string,
 *  notes: string
 * }
 *
 * Usage (Express route example):
 *
 * const multer = require('multer');
 * const memoryUpload = multer({ storage: multer.memoryStorage() });
 * const grading = require('./services/grading_engine');
 *
 * app.post('/api/grade', memoryUpload.single('image'), async (req, res) => {
 *   if (!req.file || !req.file.buffer) return res.status(400).json({ error: 'image buffer required' });
 *   const report = await grading.gradeBuffer(req.file.buffer, { cardType: req.body.cardType });
 *   return res.json({ ok: true, ...report });
 * });
 *
 * Implementation notes:
 * - This is a modular, self-contained Phase 1 implementation providing deterministic,
 *   explainable heuristics for Centering, Corners, Edges, and Surface analysis.
 * - Replace or augment the heuristics with the production CV pipeline in Phase 2.
 */

// Small utility functions
const clamp = (v, a = 0, b = 100) => Math.max(a, Math.min(b, v));

function mean(arr) { if (!arr.length) return 0; return arr.reduce((s, x) => s + x, 0) / arr.length; }
function sum(arr) { return arr.reduce((s, x) => s + x, 0); }
function stddev(arr) {
  const m = mean(arr); return Math.sqrt(mean(arr.map(x => (x - m) * (x - m))));
}

// compute simple 1D gradient absolute for array
function gradientAbs(arr) {
  const g = new Float32Array(Math.max(0, arr.length - 1));
  for (let i = 0; i < g.length; i++) g[i] = Math.abs(arr[i + 1] - arr[i]);
  return g;
}

async function gradeBuffer(buffer, options = {}) {
  options = Object.assign({ maxDim: 900, debug: false, cardType: 'generic' }, options);

  // Defensive early exit when sharp isn't available: return a stable, non-throwing fallback report.
  if (!sharp) {
    return {
      centering: 0,
      corners: 0,
      edges: 0,
      surface: 0,
      weighted: 0,
      label: 'Unknown',
      notes: 'grading skipped: optional dependency `sharp` not installed'
    };
  }

  try {
    // 1) Preprocess: rotate to correct orientation, resize to reasonable processing size,
    // convert to greyscale and normalize to reduce smartphone sharpening artifacts.
    let img = sharp(buffer, { failOnError: false }).rotate();

    // Resize so max(width,height) <= maxDim for performance
    const metadata = await img.metadata();
    const ratio = Math.max(metadata.width || 1, metadata.height || 1) / options.maxDim;
    if (ratio > 1) img = img.resize({ width: Math.round((metadata.width || 1) / ratio), height: Math.round((metadata.height || 1) / ratio) });

    // Apply gentle blur to help remove computational sharpening artifacts; we still keep structure for analysis.
    img = img.greyscale().normalize().blur(1);

    // Get raw pixel buffer (single channel since greyscale)
    const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
    const width = info.width;
    const height = info.height;
    const channels = info.channels; // should be 1 (greyscale)

    // Convert data (Uint8) into a numeric array of brightness values 0..255
    // data is Buffer; create Uint8Array view
    const pixels = new Uint8Array(data);

    // Helper to get pixel at x,y
    const idx = (x, y) => (y * width + x) * channels;
    function getPixel(x, y) {
      const i = idx(x, y);
      return pixels[i];
    }

    // 2) Estimate background (assume border areas mostly background). We'll sample 6 columns/rows from edges
    const sampleCols = 6;
    const leftCols = [];
    const rightCols = [];
    for (let x = 0; x < Math.min(sampleCols, width); x++) {
      let col = 0;
      for (let y = 0; y < height; y++) col += getPixel(x, y);
      leftCols.push(col / height);
    }
    for (let x = width - Math.min(sampleCols, width); x < width; x++) {
      let col = 0;
      for (let y = 0; y < height; y++) col += getPixel(x, y);
      rightCols.push(col / height);
    }
    const topRows = [];
    const bottomRows = [];
    for (let y = 0; y < Math.min(sampleCols, height); y++) {
      let row = 0;
      for (let x = 0; x < width; x++) row += getPixel(x, y);
      topRows.push(row / width);
    }
    for (let y = height - Math.min(sampleCols, height); y < height; y++) {
      let row = 0;
      for (let x = 0; x < width; x++) row += getPixel(x, y);
      bottomRows.push(row / width);
    }

    const bgLeft = mean(leftCols);
    const bgRight = mean(rightCols);
    const bgTop = mean(topRows);
    const bgBottom = mean(bottomRows);
    const bgApprox = mean([bgLeft, bgRight, bgTop, bgBottom]);

    // 3) Find card bounding box by scanning for columns/rows that deviate from background by threshold
    const colAvgs = new Float32Array(width);
    for (let x = 0; x < width; x++) {
      let col = 0;
      for (let y = 0; y < height; y++) col += getPixel(x, y);
      colAvgs[x] = col / height;
    }
    const rowAvgs = new Float32Array(height);
    for (let y = 0; y < height; y++) {
      let row = 0;
      for (let x = 0; x < width; x++) row += getPixel(x, y);
      rowAvgs[y] = row / width;
    }

    // Threshold relative to bgApprox: columns/rows significantly different indicate card content
    const threshold = 10; // brightness difference
    let leftEdge = 0;
    for (let x = 0; x < width; x++) {
      if (Math.abs(colAvgs[x] - bgApprox) > threshold) { leftEdge = x; break; }
    }
    let rightEdge = width - 1;
    for (let x = width - 1; x >= 0; x--) {
      if (Math.abs(colAvgs[x] - bgApprox) > threshold) { rightEdge = x; break; }
    }
    let topEdge = 0;
    for (let y = 0; y < height; y++) {
      if (Math.abs(rowAvgs[y] - bgApprox) > threshold) { topEdge = y; break; }
    }
    let bottomEdge = height - 1;
    for (let y = height - 1; y >= 0; y--) {
      if (Math.abs(rowAvgs[y] - bgApprox) > threshold) { bottomEdge = y; break; }
    }

    // Guard: if we failed to detect, fall back to full image
    if (rightEdge <= leftEdge || bottomEdge <= topEdge) {
      leftEdge = 0; rightEdge = width - 1; topEdge = 0; bottomEdge = height - 1;
    }

    const cardWidth = rightEdge - leftEdge + 1;
    const cardHeight = bottomEdge - topEdge + 1;

    // 4) Centering metric (horizontal and vertical). We compute margins as pixels and compare balance.
    const leftMargin = leftEdge;
    const rightMargin = width - 1 - rightEdge;
    const topMargin = topEdge;
    const bottomMargin = height - 1 - bottomEdge;

    // Normalize margins to image dimension
    const horizImbalance = Math.abs(leftMargin - rightMargin) / Math.max(1, width);
    const vertImbalance = Math.abs(topMargin - bottomMargin) / Math.max(1, height);
    // Convert to 0..100 where 100 is perfectly centered
    let centeringScore = Math.round((1 - (horizImbalance + vertImbalance) / 2) * 100);
    centeringScore = clamp(centeringScore);

    // 5) Edge quality: sample a narrow strip (5px) inside the card boundary and compute gradient magnitude
    function sampleEdgeStrength(stripPx = 6) {
      const strengths = [];
      const s = Math.min(stripPx, Math.floor(cardWidth / 4), Math.floor(cardHeight / 4));
      // left strip
      for (let x = leftEdge; x < leftEdge + s; x++) {
        const col = new Float32Array(cardHeight);
        for (let y = topEdge; y <= bottomEdge; y++) col[y - topEdge] = getPixel(x, y);
        strengths.push(mean(gradientAbs(col)));
      }
      // right strip
      for (let x = rightEdge - s + 1; x <= rightEdge; x++) {
        const col = new Float32Array(cardHeight);
        for (let y = topEdge; y <= bottomEdge; y++) col[y - topEdge] = getPixel(x, y);
        strengths.push(mean(gradientAbs(col)));
      }
      // top strip
      for (let y = topEdge; y < topEdge + s; y++) {
        const row = new Float32Array(cardWidth);
        for (let x = leftEdge; x <= rightEdge; x++) row[x - leftEdge] = getPixel(x, y);
        strengths.push(mean(gradientAbs(row)));
      }
      // bottom strip
      for (let y = bottomEdge - s + 1; y <= bottomEdge; y++) {
        const row = new Float32Array(cardWidth);
        for (let x = leftEdge; x <= rightEdge; x++) row[x - leftEdge] = getPixel(x, y);
        strengths.push(mean(gradientAbs(row)));
      }
      // higher gradient magnitude = cleaner crisp edge; lower -> possible wear/silvering
      return mean(strengths);
    }

    const edgeStrength = sampleEdgeStrength(6); // raw units of brightness gradient
    // We must map edgeStrength into 0..100. Heuristic: typical values range small; normalize by image depth
    // We'll compute a reference gradient from across the card center as baseline
    const centerRow = Math.floor(topEdge + cardHeight / 2);
    const centerProfile = new Float32Array(cardWidth);
    for (let x = leftEdge; x <= rightEdge; x++) centerProfile[x - leftEdge] = getPixel(x, centerRow);
    const centerGrad = mean(gradientAbs(centerProfile)) + 0.001;
    // ratio: edgeStrength relative to center gradient
    let edgeScore = Math.round(clamp((edgeStrength / centerGrad) * 50, 0, 100));
    // Favor higher = better, but clamp
    edgeScore = clamp(edgeScore);

    // 6) Corner quality: compute energy in corner blocks and estimate roundness by comparing diagonal gradients
    function cornerScoreAt(cx, cy, size = 24) {
      // cx,cy are corner top-left coords for sampling region inside the card
      const w = Math.min(size, cardWidth, cardHeight);
      const samples = [];
      for (let y = cy; y < cy + w && y <= bottomEdge; y++) {
        for (let x = cx; x < cx + w && x <= rightEdge; x++) {
          samples.push(getPixel(x, y));
        }
      }
      const sdev = stddev(samples);
      // compute small diagonal difference
      let diagDiffSum = 0; let diagCount = 0;
      for (let i = 0; i < Math.min(w - 1, 8); i++) {
        const px1 = getPixel(cx + i, cy + w - 1 - i);
        const px2 = getPixel(cx + i + 1, cy + w - 1 - (i + 1));
        diagDiffSum += Math.abs(px1 - px2); diagCount++;
      }
      const diagMean = diagCount ? diagDiffSum / diagCount : 0;
      // Heuristic: corners with higher sdev and sharper diag differences indicate well-defined sharp corners.
      const raw = (sdev + diagMean) / 2;
      return raw;
    }

    // sample 3x3 corner regions slightly inset from detected bounding box to avoid background sampling
    const inset = Math.max(4, Math.round(Math.min(cardWidth, cardHeight) * 0.02));
    const tl = cornerScoreAt(leftEdge + inset, topEdge + inset, Math.min(28, cardWidth, cardHeight));
    const tr = cornerScoreAt(rightEdge - Math.min(28, cardWidth, cardHeight) - inset + 1, topEdge + inset, Math.min(28, cardWidth, cardHeight));
    const bl = cornerScoreAt(leftEdge + inset, bottomEdge - Math.min(28, cardWidth, cardHeight) - inset + 1, Math.min(28, cardWidth, cardHeight));
    const br = cornerScoreAt(rightEdge - Math.min(28, cardWidth, cardHeight) - inset + 1, bottomEdge - Math.min(28, cardWidth, cardHeight) - inset + 1, Math.min(28, cardWidth, cardHeight));

    const cornerRawMean = mean([tl, tr, bl, br]) + 0.0001;
    // Map to 0..100
    let cornersScore = Math.round(clamp((cornerRawMean / (centerGrad + 1)) * 120, 0, 100));
    cornersScore = clamp(cornersScore);

    // 7) Surface quality: detect fine high-frequency artifacts (scratches / print lines)
    // We'll compute difference between the (slightly) blurred version and a stronger-blurred baseline to highlight scratches
    const baseBlur = 4; // stronger blur
    const { data: blurredData } = await sharp(buffer).rotate().resize({ width }).greyscale().normalize().blur(baseBlur).raw().toBuffer({ resolveWithObject: false }).then(d => ({ data: d }));
    // blurredData is Buffer of length width*height
    const diffs = new Float32Array(width * height);
    let highCount = 0;
    const total = width * height;
    for (let i = 0; i < total; i++) {
      const a = pixels[i];
      const b = blurredData[i];
      const d = Math.abs(a - b);
      diffs[i] = d;
      if (d > 18) highCount++; // threshold for scratch-like features
    }
    const highRatio = highCount / total; // fraction of pixels that are high-diff
    // Map to surface score: more high-diff -> worse surface
    let surfaceScore = Math.round(clamp((1 - highRatio * 4) * 100, 0, 100));
    surfaceScore = clamp(surfaceScore);

    // 8) Weighted final score using configurable weights (Phase 1 default equal weights)
    const weights = Object.assign({ centering: 0.25, corners: 0.25, edges: 0.25, surface: 0.25 }, options.weights || {});
    const weighted = Math.round(
      centeringScore * weights.centering +
      cornersScore * weights.corners +
      edgeScore * weights.edges +
      surfaceScore * weights.surface
    );

    // 9) Label mapping
    const label = weighted >= 95 ? 'Gem Mint' : weighted >= 90 ? 'Mint' : weighted >= 80 ? 'Near Mint' : weighted >= 70 ? 'Excellent' : 'Good';

    const notes = 'Phase 1 heuristics using sharp; replace with the production CV pipeline for final scoring.';

    const report = {
      centering: Math.round(centeringScore),
      corners: Math.round(cornersScore),
      edges: Math.round(edgeScore),
      surface: Math.round(surfaceScore),
      weighted: clamp(weighted),
      label,
      notes
    };

    if (options.debug) {
      report.debug = {
        width, height, leftEdge, rightEdge, topEdge, bottomEdge, cardWidth, cardHeight,
        bgApprox, edgeStrength, centerGrad, highRatio
      };
    }

    return report;
  } catch (err) {
    // On unexpected errors return a defensive fallback report
    return {
      centering: 0,
      corners: 0,
      edges: 0,
      surface: 0,
      weighted: 0,
      label: 'Unknown',
      notes: `grading engine error: ${err.message}`
    };
  }
}

module.exports = { gradeBuffer };