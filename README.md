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
3. Open http://localhost:3000

Notes:
- Uploaded images are stored in `./uploads` during Phase 1. Replace with cloud storage in production.
- Grading logic is mocked in server.js (function mockGradeImage). Replace with the real CV pipeline in Phase 2.
