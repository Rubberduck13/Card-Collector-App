'use strict';
/**
 * services/grading_engine.js
 * Phase 2: Server-side card centering grader (pixel-border scanning)
 *
 * Usage (Express + multer memory storage):
 *
 * const { gradeCardImage } = require('./services/grading_engine');
 *
 * app.post('/api/grade', upload.single('image'), async (req, res) => {
 *   try {
 *     const result = await gradeCardImage(req.file.buffer);
 *     res.json(result);
 *   } catch (err) {
 *     console.error('Grading error:', err);
 *     res.status(500).json({ error: 'Grading failed' });
 *   }
 * });
 *
 * Notes:
 * - This function uses `sharp` to decode and normalize the image, then scans
 *   multiple perpendicular sample lines from each edge to detect the card frame
 *   boundary using luminance gradients. It returns pixel thicknesses and
 *   centering ratios for horizontal and vertical axes in the exact JSON format
 *   requested by the frontend.
 */

const sharp = require('sharp');

// Configuration / tunables
const MAX_DIMENSION = 1200; // resize longest side to this for performance
const NUM_SAMPLES_PER_SIDE = 21; // odd number helps with median
const MIN_EDGE_THRESHOLD = 9; // minimum luminance diff to consider an edge

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

async function decodeToGray(buffer) {
  // Read image, rotate according to EXIF, resize for performance, get raw RGBA
  const image = sharp(buffer, { failOnError: false }).rotate();
  const metadata = await image.metadata();

  const width = metadata.width;
  const height = metadata.height;
  if (!width || !height) throw new Error('Could not determine image dimensions');

  let resizeNeeded = Math.max(width, height) > MAX_DIMENSION;
  const resized = resizeNeeded ? image.resize({
    width: width >= height ? MAX_DIMENSION : null,
    height: height > width ? MAX_DIMENSION : null,
    fit: 'inside'
  }) : image;

  const { data, info } = await resized.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  // Convert RGBA to grayscale luminance array (Float32Array)
  const w = info.width;
  const h = info.height;
  const lum = new Float32Array(w * h);
  for (let i = 0, p = 0; i < lum.length; i++, p += 4) {
    const r = data[p];
    const g = data[p + 1];
    const b = data[p + 2];
    // linear luminance approximation
    lum[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  return { lum, width: w, height: h };
}

function getIndex(x, y, width) { return y * width + x; }

function samplePositions(length, count) {
  // return `count` integer positions evenly spaced between 10% and 90% (inclusive)
  const start = Math.floor(length * 0.1);
  const end = Math.ceil(length * 0.9);
  if (count === 1) return [Math.floor((start + end) / 2)];
  const step = (end - start) / (count - 1);
  const out = [];
  for (let i = 0; i < count; i++) out.push(clamp(Math.round(start + i * step), 0, length - 1));
  return out;
}

function median(arr) {
  const a = arr.slice().filter(v => Number.isFinite(v)).sort((x, y) => x - y);
  if (a.length === 0) return NaN;
  const mid = Math.floor(a.length / 2);
  return a.length % 2 === 1 ? a[mid] : (a[mid - 1] + a[mid]) / 2;
}

function detectEdgeThicknessOnLine(lineLum, fromEdge = 'left') {
  // lineLum: Float32Array of luminance values along one scanline
  // fromEdge: 'left' | 'right' - direction we scan inward
  const n = lineLum.length;
  // compute diffs
  const diffs = new Float32Array(n - 1);
  let sum = 0;
  for (let i = 0; i < n - 1; i++) {
    const d = Math.abs(lineLum[i + 1] - lineLum[i]);
    diffs[i] = d;
    sum += d;
  }
  const meanDiff = sum / Math.max(1, diffs.length);
  // compute std dev (small sample), to make threshold adaptive
  let sd = 0;
  for (let i = 0; i < diffs.length; i++) sd += Math.pow(diffs[i] - meanDiff, 2);
  sd = Math.sqrt(sd / Math.max(1, diffs.length));
  const threshold = Math.max(MIN_EDGE_THRESHOLD, meanDiff + sd * 2.5);

  // scan from requested edge and find the first diff exceeding threshold
  if (fromEdge === 'left') {
    for (let i = 0; i < diffs.length; i++) {
      if (diffs[i] >= threshold) {
        // thickness is number of pixels from edge before the strong gradient
        return i + 1; // +1 to count pixel after diff
      }
    }
  } else {
    for (let i = diffs.length - 1; i >= 0; i--) {
      if (diffs[i] >= threshold) {
        return (n - 1 - i) + 1; // pixels from right edge
      }
    }
  }
  // if no strong gradient found, fallback to small thickness
  return 0;
}

function extractLineLuminances(lum, width, height, orientation, fixedCoord) {
  // orientation: 'vertical' (x fixed, sample y increasing) or 'horizontal' (y fixed, sample x increasing)
  if (orientation === 'vertical') {
    const x = fixedCoord;
    const arr = new Float32Array(height);
    for (let y = 0; y < height; y++) arr[y] = lum[getIndex(x, y, width)];
    return arr;
  } else {
    const y = fixedCoord;
    const arr = new Float32Array(width);
    for (let x = 0; x < width; x++) arr[x] = lum[getIndex(x, y, width)];
    return arr;
  }
}

async function gradeCardImage(buffer) {
  if (!buffer || !Buffer.isBuffer(buffer)) throw new Error('gradeCardImage requires a Buffer (req.file.buffer)');
  const { lum, width, height } = await decodeToGray(buffer);

  // Prepare sample positions
  const ySamples = samplePositions(height, NUM_SAMPLES_PER_SIDE);
  const xSamples = samplePositions(width, NUM_SAMPLES_PER_SIDE);

  const leftThicknesses = [];
  const rightThicknesses = [];
  const topThicknesses = [];
  const bottomThicknesses = [];

  // For left/right: sample vertical lines at x positions (from 0.. width-1)
  for (const y of ySamples) {
    // horizontal line at y
    const line = extractLineLuminances(lum, width, height, 'horizontal', y);
    const leftT = detectEdgeThicknessOnLine(line, 'left');
    const rightT = detectEdgeThicknessOnLine(line, 'right');
    leftThicknesses.push(leftT);
    rightThicknesses.push(rightT);
  }

  // For top/bottom: sample vertical lines at x positions
  for (const x of xSamples) {
    const line = extractLineLuminances(lum, width, height, 'vertical', x);
    const topT = detectEdgeThicknessOnLine(line, 'left'); // top -> from start of vertical array
    const bottomT = detectEdgeThicknessOnLine(line, 'right');
    topThicknesses.push(topT);
    bottomThicknesses.push(bottomT);
  }

  // Use median to be robust against outliers
  const leftPx = Math.round(median(leftThicknesses));
  const rightPx = Math.round(median(rightThicknesses));
  const topPx = Math.round(median(topThicknesses));
  const bottomPx = Math.round(median(bottomThicknesses));

  // Safety: if all zeros (failed detection), try smaller heuristics or return zeros
  const horSum = leftPx + rightPx;
  const verSum = topPx + bottomPx;

  let leftPct = 50, rightPct = 50, topPct = 50, bottomPct = 50;
  if (horSum > 0) {
    leftPct = +(leftPx / horSum * 100).toFixed(2);
    rightPct = +(rightPx / horSum * 100).toFixed(2);
  }
  if (verSum > 0) {
    topPct = +(topPx / verSum * 100).toFixed(2);
    bottomPct = +(bottomPx / verSum * 100).toFixed(2);
  }

  const centering = {
    horizontal: `${Math.round(leftPct)}/${Math.round(rightPct)}`,
    vertical: `${Math.round(topPct)}/${Math.round(bottomPct)}`
  };

  return {
    leftPx,
    rightPx,
    topPx,
    bottomPx,
    leftPct,
    rightPct,
    topPct,
    bottomPct,
    centering
  };
}

module.exports = { gradeCardImage };
