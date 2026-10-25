# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS desktop

## Stack

AppKit manages desktop-level wallpaper windows and the menu bar. A same-origin local WKWebView page renders the wallpaper as a read-only data board (quotas, today, request anatomy, and the hourly rhythm). Account quotas, cache hit rate, token statistics and recent operation consumption are always on the wallpaper; a separate native detail window expands request attribution. SwiftUI remains for preferences and the optional legacy widget/screen saver. No web hosting or CDN is needed.

## Users

The primary user is a single Mac operator who uses Magpie to route Codex and other AI-agent traffic across multiple providers and accounts. They want the Magpie data modules as a desktop wallpaper — today/week/month usage, quotas, hourly rhythm, rankings and recent calls, plus a request-anatomy panel showing model/provider distribution, recent latency phases, and token/context composition. Decorative token-flow staging with invented or demo traffic remains out of scope; so do a desktop pet and switchable visual themes.

## Product Purpose

Turn local Magpie telemetry into a glanceable desktop wallpaper. Success means the user can read today’s usage, request anatomy and remaining quotas without opening Magpie. The operational widget and automatic screen saver remain optional secondary surfaces.

## Positioning

This is not a generic system monitor and not a remote cloud dashboard. It visualizes the actual local Magpie gateway in real time, using its local HTTP telemetry as the source of truth and presenting those modules as the desktop wallpaper and screen saver.

## Operating Context

Magpie runs locally at `127.0.0.1:3425`. The app polls its usage, quota, request, and trace endpoints. The widget stays above ordinary windows and can be moved or hidden. After a configurable period without keyboard or pointer activity, the same full-screen data board appears; any input dismisses it. Email addresses should be masked by default in passive views.

## Capabilities and Constraints

- Live today / 7-day / 30-day / all-time usage summaries from `/v1/magpie/usage`.
- Provider/account quota windows from `/v1/magpie/quotas`.
- Request-ledger aggregates and per-call rows from `/v1/magpie/usage/requests`; current in-flight count from `/v1/magpie/trace`.
- Desktop wallpaper presenting quotas, today's spend and cache rate, and a request-anatomy panel with model/provider call and failure distribution, up to 18 recent total/TTFT/generation timings, and per-model cache-read/input/output/reasoning token composition.
- Missing timing fields such as transport or gateway duration are reported as unavailable and never inferred or summed into a synthetic waterfall.
- Wallpaper below desktop icons with mouse passthrough.
- Menu-bar controls and optional legacy widget/screen-saver mode.
- Trace and request-ledger polling is discrete (about one second); heavier usage and quota data refreshes about every four seconds. The board shows only what the gateway returned, with no interpolation or invented traffic.
- A clear offline state when Magpie is unavailable; demo data may be used only as an explicitly labelled preview.
- No screen recording, OCR, cloud upload, or account credentials are used.

## Brand Commitments

The wallpaper is a local data-center operations wall (NOC): dense instrument cabinets on a blueprint-grid ground, expressive light, but every glowing element must answer to a real data state — in flight, failed, low, near reset, offline. Ambient motion is limited to one slow scan sheen, quota-bar glints, and a brief corner blink when a new real request enters the ledger. No Three.js scene, no particle seas, no invented traffic. The existing Magpie identity and local-first nature should remain recognizable; the visual language may be expressive but must not imply that this is an official Magpie product.

## Evidence on Hand

Live local API responses were verified on 2026-10-22, including usage, quota, request, and trace payloads. Magpie 0.1.1319 is installed at `/Applications/magpie.app` with bundle id `com.yetone.magpie`.

## Product Principles

1. Show real local truth, never invent live activity.
2. Make request anatomy legible: model/provider distribution, latency phases, and context composition.
3. Keep the board dense and glanceable; expressiveness comes from light on real state, never from invented motion.
4. Degrade honestly and recover automatically when Magpie reconnects.
5. Respect privacy by masking account identifiers in ambient views.

## Accessibility & Inclusion

Use sufficient contrast, support Reduce Motion by simplifying or stopping decorative particles, expose controls through native keyboard focus and accessibility labels, and allow the screen saver to be dismissed by any input.
