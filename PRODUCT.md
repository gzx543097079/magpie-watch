# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS desktop

## Stack

AppKit manages desktop-level wallpaper windows, the independently draggable pet panel and menu bar. A same-origin local WKWebView page renders the wallpaper as a read-only data board (quotas, today, live route stream, agents); original dsh-whale-musume WebP poses, MIT state core and CSS/WAAPI render the pet. The pet workbench exposes outfits and actions only. Account quotas, cache hit rate, token statistics and recent operation consumption are always on the wallpaper; a separate native detail window expands request attribution. SwiftUI remains for preferences and the optional legacy widget/screen saver. No web hosting or CDN is needed.

## Users

The primary user is a single Mac operator who uses Magpie to route Codex and other AI-agent traffic across multiple providers and accounts. They want the Magpie data modules as a desktop wallpaper — today/week/month usage, quotas, hourly rhythm, rankings and recent calls — plus an independently movable pet with multiple switchable appearances. Token-flow staging is out of scope.

## Product Purpose

Turn local Magpie telemetry into a glanceable desktop wallpaper and a playful companion. Success means the user can read today’s usage and remaining quotas without opening Magpie, drag the pet anywhere, and choose between distinct characters. The operational widget and automatic screen saver remain optional secondary surfaces.

## Positioning

This is not a generic system monitor and not a remote cloud dashboard. It visualizes the actual local Magpie gateway in real time, using its local HTTP telemetry as the source of truth and presenting those modules as the desktop wallpaper and screen saver.

## Operating Context

Magpie runs locally at `127.0.0.1:3425`. The app polls its usage, quota, request, and trace endpoints. The widget stays above ordinary windows and can be moved or hidden. After a configurable period without keyboard or pointer activity, the same full-screen data board appears; any input dismisses it. Email addresses should be masked by default in passive views.

## Capabilities and Constraints

- Live today / 7-day / 30-day / all-time usage summaries from `/v1/magpie/usage`.
- Provider/account quota windows from `/v1/magpie/quotas`.
- Recent route and fallback activity from `/v1/magpie/usage/requests` and `/v1/magpie/trace`.
- Desktop wallpaper presenting quotas, today's spend and cache rate, a live route stream (latency, TTFT, failures, model/folder mix, recent calls) and agent rankings.
- Wallpaper below desktop icons with mouse passthrough; a separate floating pet panel with persisted position and skin.
- Menu-bar controls and optional legacy widget/screen-saver mode.
- Trace polling is discrete (about four seconds); the board shows only what the gateway returned, with no interpolation or invented traffic.
- Pet artwork is animated with CSS rather than a Live2D rig.
- A clear offline state when Magpie is unavailable; demo data may be used only as an explicitly labelled preview.
- No screen recording, OCR, cloud upload, or account credentials are used.

## Brand Commitments

The wallpaper is a calm instrument panel rather than an animated spectacle: no Three.js scene, no ambient motion. The pet remains playful and draggable with multiple character choices. The existing Magpie identity and local-first nature should remain recognizable; the new visual language may be expressive but must not imply that this is an official Magpie product.

## Evidence on Hand

Live local API responses were verified on 2026-10-22, including usage, quota, request, and trace payloads. Magpie 0.1.1319 is installed at `/Applications/magpie.app` with bundle id `com.yetone.magpie`.

## Product Principles

1. Show real local truth, never invent live activity.
2. Make routing legible as motion: source, gateway, candidates, selected destination.
3. Keep passive information calm, compact, and glanceable.
4. Degrade honestly and recover automatically when Magpie reconnects.
5. Respect privacy by masking account identifiers in ambient views.

## Accessibility & Inclusion

Use sufficient contrast, support Reduce Motion by simplifying or stopping decorative particles, expose controls through native keyboard focus and accessibility labels, and allow the screen saver to be dismissed by any input.
