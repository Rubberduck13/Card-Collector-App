# CardGrade — Phase 1 Scaffold

This repository contains the Phase 1 scaffold for the CardGrade project: a Node/Express server and a responsive frontend that supports mobile camera capture and a mock grading API.

Files added:
- package.json
- server.js
- public/index.html
- public/styles.css
- public/app.js

Usage:
1. Install dependencies: `npm install`
2. Start server: `npm start` or `npm run dev` (needs nodemon)
3. Open http://localhost:5000

Notes:
- Uploaded images are stored in `./uploads` during Phase 1. Replace with cloud storage in production.
- Grading logic is mocked in server.js (function mockGradeImage). Replace with your CV pipeline and scoring module in Phase 2.

---

## Grade Endpoint (Phase 1)

We provide a memory-buffer based grade endpoint intended for low-latency server-side image processing using `multer` memory storage and the `sharp` library.

Endpoint: POST /api/grade

Request:
- Content-Type: multipart/form-data
- Fields:
  - image: file (required) — the image uploaded from the client. The server uses multer memory storage and provides `req.file.buffer`.
  - cardType: string (optional) — e.g., "sport" or "tcg". Passed into the grading engine for future conditional logic.
  - debug: boolean (optional) — if set to true, grading engine includes debugging metadata in the report.
  - weights: JSON string (optional) — custom weights for scoring, e.g. `{"centering":0.2,"corners":0.2,"edges":0.3,"surface":0.3}`.

Response (200):
- JSON

{
  "ok": true,
  "report": {
    "centering": number, // 0-100
    "corners": number,   // 0-100
    "edges": number,     // 0-100
    "surface": number,   // 0-100
    "weighted": number,  // 0-100 final score
    "label": string,     // human-friendly grade label
    "notes": string
    // optional: "debug" object when debug=true
  }
}

Errors:
- 400 for missing image buffer
- 500 for internal processing errors

Notes:
- The grading engine is implemented in `services/grading_engine.js` and uses `sharp` for image preprocessing. Replace with a production CV pipeline in Phase 2 and persist images to object storage (S3/GCS) rather than memory/disk when scaling.
