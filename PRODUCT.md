# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Stack

delegated: native macOS application built with Swift 6, SwiftUI, and AppKit. This is required for an always-on-top desktop panel, a menu-bar controller, direct local HTTP access to Magpie, and an immersive full-screen screen-saver mode.

## Users

The primary user is a single Mac operator who uses Magpie to route Codex and other AI-agent traffic across multiple providers and accounts. They want live usage, quota, and routing activity available at a glance while working, and a calm animated routing view when the Mac is idle.

## Product Purpose

Turn Magpie's local usage and routing telemetry into a native desktop companion: a compact floating widget for operational awareness and an automatically appearing full-screen routing screen saver. Success means the user can see today's consumption, account pressure, gateway health, and the currently selected route without opening the Magpie window.

## Positioning

This is not a generic system monitor and not a remote cloud dashboard. It visualizes the actual local Magpie gateway in real time, using its local HTTP telemetry as the source of truth and turning route selection into the screen saver itself.

## Operating Context

Magpie runs locally at `127.0.0.1:3425`. The app polls its usage, quota, request, and trace endpoints. The widget stays above ordinary windows and can be moved or hidden. After a configurable period without keyboard or pointer activity, a full-screen animated route view appears; any input dismisses it. Email addresses should be masked by default in passive views.

## Capabilities and Constraints

- Live today / 7-day / 30-day / all-time usage summaries from `/v1/magpie/usage`.
- Provider/account quota windows from `/v1/magpie/quotas`.
- Recent route and fallback activity from `/v1/magpie/usage/requests` and `/v1/magpie/trace`.
- Animated Agent -> Magpie gateway -> provider/account route visualization.
- Floating desktop widget, menu-bar controls, and full-screen screen-saver mode.
- A clear offline state when Magpie is unavailable; demo data may be used only as an explicitly labelled preview.
- No screen recording, OCR, cloud upload, or account credentials are used.

## Brand Commitments

The user asked for a desktop widget and a dynamic screen saver. The existing Magpie identity and local-first nature should remain recognizable; the new visual language may be expressive but must not imply that this is an official Magpie product.

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
