---
name: SafePaths
description: Existing Flutter Material 3 interface for road conditions, flood reports and navigation.
colors:
  primary: "#005AB6"
  primary-container: "#1672DF"
  surface: "#F7F9FC"
  surface-container-low: "#F2F4F7"
  on-surface: "#191C1E"
  on-surface-variant: "#414753"
  secondary: "#006E1C"
  error: "#BA1A1A"
  passable: "#22C55E"
  partial: "#EAB308"
  not-passable: "#EF4444"
  warning: "#F59E0B"
  dark-surface: "#101418"
  dark-primary: "#ABC7FF"
typography:
  headline:
    fontFamily: Manrope
    fontSize: "24px"
    fontWeight: 700
  title:
    fontFamily: Inter
    fontSize: "16px"
    fontWeight: 600
  body:
    fontFamily: Inter
    fontSize: "14px"
    fontWeight: 400
  label:
    fontFamily: Inter
    fontSize: "14px"
    fontWeight: 700
rounded:
  control: "12px"
spacing:
  field-inset: "16px"
  action-horizontal: "24px"
---

# SafePaths design system

## Overview

This documents the existing Android-targeted Flutter UI from source on 2026-11-12; it is not a redesign or a screenshot-based visual audit. Flutter renders the app; the native Android activity only hosts it. Preserve the established resident/admin workflows and task-focused interface.

Source authority: `lib/theme/app_theme.dart`, `lib/theme/app_palette.dart`, `lib/theme/app_colors.dart`, shared widgets in `lib/widgets/`, and existing screens in `lib/screens/`. Token numbers above use portable CSS notation; Flutter sizes are logical pixels, and text sizes must continue to honor system text scaling.

## Colors

Blue is the main action color. Light surfaces use the existing cool neutral backgrounds. Read context-bound colors from `AppPalette.of(context)` rather than maintaining mutable global theme state. Light `AppPalette.primaryContainer` is `#005AB6`, which differs from the base `AppColors.primaryContainer` token above; the resolved palette wins at runtime.

Dark surfaces use `#101418`, primary `#ABC7FF`, and on-surface `#E0E3E7`. Filled dark-theme primary actions use the deeper primary container (`#00458E`) through the existing palette helper. Preserve semantic map colors for passable, partial and not-passable roads; accompany color with a readable label or icon.

## Typography

Manrope defines display/headline typography and the 22-pixel large title. Inter defines body, labels and smaller titles. Existing display sizes are 57/45/36; headlines 32/28/24; body 16/14/12; labels 14/12/11. Use `Theme.of(context).textTheme` and existing roles instead of defining a new font system.

## Layout

Preserve map-first resident views, existing bottom navigation, report forms and admin workspaces. Account for safe areas, the software keyboard, small Android screens and larger text. Text fields use 16-pixel internal padding; filled actions use 24 horizontal and 16 vertical padding. These are observed component defaults, not a universal spacing scale. Keep map attribution, location controls and navigation instructions accessible.

## Elevation & Depth

Use existing surface-container tones for hierarchy. The palette's primary-action decoration supports a light-theme blue gradient and optional shadow (blur 16, offset 0/4); dark mode uses a solid container without that shadow. Preserve context-specific existing treatments rather than adding generic gradients everywhere.

## Shapes

Theme-level inputs and elevated buttons use 12-pixel corners. The primary-action decoration helper defaults to 16. Retain each existing component's shape instead of forcing all cards and controls to one radius.

## Components

Reuse `app_top_bar.dart`, `bottom_nav_bar.dart`, `admin_bottom_nav_bar.dart`, `app_map.dart` and the existing report widgets before creating replacements. Elevated actions have a theme-level minimum size of 48 by 48 logical pixels. Inputs are filled and outlined on focus. Existing page transitions use a fade with ease-out/ease-in curves.

Keep loading, unavailable, permission-denied, empty, retry and success states truthful. Clearly distinguish reported flood evidence, admin-confirmed road state and predictive risk. NOAH awareness overlays are contextual hazard information, not observed flood depth or routing instructions.

## Do's and Don'ts

- Preserve readable contrast, system text scaling, semantic labels and adequate touch targets.
- Keep resident and admin permissions visible through the existing interaction model.
- Preserve existing strings/localization and map provider attribution.
- Do not replace this Flutter UI with Compose, Android XML screens, HTML or Tailwind examples from a skill.
- Do not claim a source-derived token document proves visual quality on a device. Verify UI changes with Flutter tests and real Android rendering.
