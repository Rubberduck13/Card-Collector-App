THE JUDGE — CORE PROTOCOL & SPECIFICATION MANIFESTO
Strategic Vision, Autonomous Diagnostic Framework, & Global Valuation Architecture

ARCHITECTURE NOTE (merge record): An earlier draft of this plan ("Strategic Business Plan: Proprietary AI Sports Card Grading Platform") described a cloud/server-side computer vision pipeline — images uploaded to a Node/Express backend for processing via `grading_engine.js`. That is superseded: the actual, working implementation is a fully on-device pipeline (Vision framework + Core Image, native Swift), consistent with Section 6's "Decentralized Execution" principle below. `grading_engine.js` and the Node backend's mock grading path are known-fake legacy code, not the real pipeline, and their fate (isolate vs. retire) is still an open decision tracked separately. If a server-side track is still wanted for some other reason (e.g. bulk/enterprise batch processing at scale), it should be scoped explicitly as a distinct, later addition — not conflated with the core on-device grading pipeline this document specifies.

1. EXECUTIVE SUMMARY & VISION

"The Judge" is engineered to be the definitive global software benchmark for trading card verification, structural diagnostics, and raw market valuation — putting an automated, unbiased, instantaneous grading expert into every collector's pocket.

The Core Problem: Traditional grading (PSA, Beckett/BGS, SGC, CGC) is slow, expensive ($15–$100+ per card), and manually subjective. Existing scanning apps (Ludex, CollX) are primarily inventory/database lookup tools, or rely on rigid, paid third-party vision APIs (e.g. Ximilar) that impose per-image operating costs and limit how deeply the analysis can go.

Rather than seeking to immediately replace the physical encapsulation and serialization mechanisms of legacy grading laboratories, "The Judge" operates as an indispensable, high-utility pre-submission diagnostic ecosystem. It serves two distinct market pillars:

The Risk-Mitigation Engine: Providing collectors with flawless mathematical forecasting of legacy lab outcomes before capital is deployed on physical submission fees.
The Raw Market Trade Standard: Acting as a trusted, objective, raw-case pricing protocol for brick-and-mortar hobby shops, regional trading conventions, and peer-to-peer raw inventory transactions.

"The Judge" delivers absolute objectivity, instant multi-dimensional reports, and unconditional reproducibility. If the card's physical condition has not altered, the system will output the identical grade across infinite iterative scans.

Competitive Edge:
- vs. Legacy third-party vision APIs (e.g. Ximilar): those are bound by flat-image limitations and per-image pricing. Our edge: on-device multi-angle/video verification with zero per-image API fees, since the vision pipeline is proprietary and local rather than a metered external call.
- vs. Scanning/inventory wrappers (e.g. Ludex, CollX): those focus on database lookup over deep micro-imperfection analysis. Our edge: pre-processing and metrology aimed at true pixel-level border, edge, and surface analysis rather than identification-only scanning.

2. TARGET MARKET

1. The Casual Collector/Flipper: wants a quick smartphone scan to decide whether a card is worth the cost of physical slab grading.
2. Bulk Shop Owners: local card shops managing high-volume inventory, needing fast, standardized batch assessments.
3. TCG Players: need rapid condition tags for instant marketplace listings.

3. THE DUAL-SCALE GRADING MATRIX

To command 100% market respect from casual hobbyists and elite high-end investors alike, the system processes and displays two distinct diagnostic conclusions:

A. The Predictive Legacy Tier (Simulation Engine)

Objective: Replicate the exact, real-world grading tolerances and known leniencies of major grading bodies.
Logic Framework: Programmed to accommodate historical grading guardrails (e.g., applying PSA's standard allowance where a 60/40 horizontal centering distribution can still qualify for a Gem Mint 10 designation; Beckett/BGS trends notably stricter, closer to a 50/50 standard, at the top grade tier).

B. "The Judge" True Grade Scale (Uncompromising Precision)

Objective: Eradicate human subjectivity and institutional variance by deploying a ruthless, 100-point mathematical condition scale.
Logic Framework: A true condition metric where perfection requires exact geometric symmetry and a zero-defect surface matrix. This scale serves as the precise benchmark for pricing raw, unencapsulated cards in retail showcases.

4. ADVANCED CORE ENGINEERING & TECHNICAL PIPELINE

Every developer and AI assistant contributing to this repository must engineer features to meet the following high-proficiency multi-frame computer vision parameters. All processing below is on-device (see Architecture Note) — no image data is sent to an external server or third-party vision API as part of the core grading pipeline.

A. Guided Ingestion & Orientation Spatial Grid

The frontend must deploy a high-contrast responsive viewport framing overlay. This forces standard spatial orientation and physical card distance initialization to minimize mathematical skew.

A capture environment standard is part of this spec, not optional guidance: consistent lighting (a fixed or diffused light source, not ambient/mixed lighting), a neutral high-contrast backing mat (not a surface close in brightness to typical card borders), and a fixed phone-to-card distance. Legacy grading labs achieve their measurement consistency primarily through controlled capture conditions (flatbed scanners, studio lighting), not exotic algorithms — the capture standard is load-bearing for accuracy, not cosmetic.

A0. Anti-Distortion Pre-Processing Pass

Modern smartphone cameras apply computational photography (sharpening, noise smoothing, HDR tone-mapping) before an app ever sees the pixel data. This is not cosmetic — sharpening in particular can inject false contrast/haloing directly at high-contrast transitions like card borders, which is a plausible contributor to spurious edge-detection triggers seen in real testing (e.g. divergence firing immediately adjacent to the true border rather than at it). Before any centering, edge, or surface metrology runs, captured frames should pass through an on-device normalization step that flattens sharpening-induced artifacts back toward a more raw pixel representation. This is a data-quality gate ahead of the measurement code, not a substitute for fixing the measurement code itself.

B. Specular Reflection Multi-Frame Surface Analysis (Live Video Stream)

The Challenge: Flat, single-perspective digital capture cannot visualize microscratches, faint print lines, surface dimples, or indentation defects.
The Protocol: The system initializes a guided "Condition Sweep," capturing live video streams at 30 frames per second over a 3-to-5 second window while prompting the user to rotate or tilt the phone smoothly under direct lighting.
The Algorithmic Logic: The backend analyzes rapid pixel-level contrast fluctuations (specular glare transitions). Persistent anomalies that reflect light uniformly across multiple angles are mathematically isolated and logged as confirmed structural blemishes (scratches, dimples, fading, or print lines).

C. Sub-Pixel Geometric Edge & Corner Metrology — Dual-Track Centering Architecture

REVISED: Centering detection is not a single algorithm — it is a dispatch between two structurally different methods, selected per card, because a meaningful fraction of the modern card market (full-bleed/borderless parallels, edge-to-edge print designs) has no physical border for a border-ratio method to measure at all. Treating this as one algorithm with edge cases has been a source of real measurement failures; it needs to be treated as two methods with a selection step.

Track 1 — Bordered Cards (physical border present):
- Border-width ratio detection, upgraded to detect the border-to-art transition via multi-channel color deltas (not averaged single-channel brightness alone) — brightness-only thresholding is unreliable specifically on white/light borders photographed against light-colored backing, which is a common real-world case, not an edge case.
- Validated on an ongoing basis against a physical reference card with a precisely known, pre-measured border — every algorithm change is checked against this known-answer target before being trusted on unknown cards, rather than each change being evaluated only against visual plausibility.

Track 2 — Borderless / Full-Bleed Cards (no physical border to measure):
- Centering is inferred from feature-based image registration: detecting fixed print elements (team wordmarks, nameplate position, logo placement, holofoil pattern anchors) and measuring their offset against a known-good reference template of that exact card/parallel, rather than measuring a border width that does not exist.
- Requires a per-set/per-parallel template reference library — this is a genuinely larger engineering undertaking than Track 1 (template acquisition/maintenance, keypoint/homography matching per card design) and should be scoped and resourced as its own workstream, not treated as a variant of Track 1.

Card Type Classification: A detection step (border presence/absence, ideally corroborated by set/parallel identification from the variant discrimination pipeline in Section 4E) determines which track a given scan is routed through before centering analysis runs. Misrouting a borderless card into Track 1 is an expected failure mode to guard against explicitly, not an occasional bug.

Edges: Tracking slight angular perspective shifts along the card profile to identify edge chipping, coloring wear, and multi-layer paper pulp separation.

Corners: Mathematically measuring the true radius curvature of all four points to detect microscopic rounding, soft stock, soft impacts, or structural bends. Corner analysis uses separate profiles per card category rather than one universal model: Sports Cards are evaluated against a sharp, near-90-degree corner standard, while TCG Cards (Pokémon, Magic, etc.) are evaluated against their characteristically more rounded manufactured corner radius — applying the sports standard to a TCG card (or vice versa) produces systematically wrong wear readings.

D. Proprietary Scoring Module

The scoring formula that converts raw sub-grade measurements (centering, edges, corners, surface) into a final grade is kept isolated from the vision/measurement layer, so sub-grade weights can be tuned (e.g. weighting surface scratches more heavily for holofoil/chrome finishes, where they're more visually significant) without touching or re-validating the underlying measurement code.

E. Fine-Grained Deep Variant Discrimination

Integrated image fingerprinting combined with targeted OCR parsers. The app must autonomously distinguish between complex parallels (e.g., separating a Base card from a Silver Prizm, Refractor, Holo, short-print, or limited serial-numbered variation) based on surface text orientation and localized pixel arrays.

This classification output feeds Section 4C's track-routing decision and, for Track 2, selects which reference template to register against.

5. MONETIZATION STRATEGY (SCALABLE TIERS)

Tier 1: Free Tier (The Hook)
- Full access to the UI and basic card inventory wallet.
- Limited automated scans per month.
- Basic community market comparisons.

Tier 2: Premium Collector (Subscription)
- Unlimited scans with detailed pixel visual overlay reports.
- Cross-device cloud backup (iPhone, iPad, Mac web sync).
- Premium market price integration.

Tier 3: Enterprise/Shop Owner (High Volume)
- Bulk processing pipelines compatible with high-speed sheet-fed document scanners.
- CSV/data inventory exports tailored for direct eBay, TCGPlayer, or Shopify ingestion.

6. FUTURE NEURAL ARCHITECTURE ROADMAP

Decentralized Execution: Core image metrology matrices must compile to lightweight, on-device client-side scripts to remain exceptionally fast, highly scalable, and completely independent of expensive third-party vision APIs. (See Architecture Note — this is the confirmed, actual direction, not the earlier cloud-server draft.)

Self-Optimizing Model Feedback: Anonymized diagnostic vectors, plus user-flagged correction loops (trusted users flagging incorrect AI outputs), will securely loop into a proprietary database registry, allowing the alignment neural network to scale its contextual intelligence with every verified scan worldwide.

7. SCOPED SERVER-SIDE TRACK (RESOLVES ARCHITECTURE NOTE)

Decision: the core grading pipeline (centering, edges, corners, surface) remains on-device for the primary iOS app, permanently — not a phased migration toward a server. A server-side component is still real and necessary, but only for responsibilities that are inherently central, never for the grading math itself on iOS:

1. Track 2 Template Library Hosting: the per-set/per-parallel reference template library (Section 4C, Track 2) must be centrally maintained and distributed — new sets release constantly, and no device should be expected to permanently embed every template ever created. The server's job here is distribution and versioning, not measurement.
2. Cross-Device Sync & Pricing (Tier 2): cloud backup and live market price integration are inherently server-backed already; no change needed, just formal acknowledgment that this is the server's actual job.
3. Self-Optimizing Feedback Loop (Section 6): anonymized diagnostic vectors and user correction flags necessarily aggregate centrally to retrain the proprietary model — this was already implicitly server-side and stays that way.
4. Enterprise/Shop Bulk Tier (Tier 3) — Scoped Exception: high-volume sheet-fed scanner ingestion is plausibly a desktop/web surface rather than iOS, meaning it has no access to Apple's Vision framework. If/when this tier is built, it is expected to need its own server-side port of the same centering/edge/corner algorithms (e.g. Python/OpenCV) to serve that surface specifically. This is a deliberate, scoped exception for a non-iOS surface — it does not imply moving the iOS app's own pipeline off-device, and the two implementations (on-device Swift, server-side port) must be validated to produce matching results against the same reference card, not developed as independently-evolving codebases.

8. EXECUTION GUIDELINES FOR CONTRIBUTORS (HUMAN OR AI)

1. Keep the code modular: helper files and processing logic live in separate, isolated components. Do not lump interface styling and image-processing calculations into single massive scripts. Future algorithm updates or model replacements should plug in without rewriting the core.
2. Document with intent: functions carry structured comments so future development cycles can extend modules without re-deriving their logic from scratch.
3. UI must be fully responsive and touch-optimized for iPhone and iPad.
