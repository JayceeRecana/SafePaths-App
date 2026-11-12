# Map overlay after returning from photo selection

## Observed behavior

The supplied 39.96-second resident recording shows the report form, the photo-source sheet and the external Android gallery. Around 33-39 seconds, after an image is selected, the returning app draws map imagery over the report fields. A Photo attached successfully message still appears. This establishes a native display-order problem in that recorded report flow; it does not establish that uploading or saving the report failed. The user reports the same overlap when changing a profile photo; that second path is not shown in this clip. Private gallery contents are excluded from this review.

## Shared fix

AppMap forced Android hybrid composition with textureView false. The underlying map remains mounted behind report/profile routes. An independent Android SurfaceView returning above the Flutter route is consistent with the observed symptom; device confirmation is still required to establish the fix on the affected phone.

The fix removes the forced hosting-mode override and explicitly enables textureView. This restores the texture-based default of the pinned mapbox_maps_flutter 2.29.1 SDK, also used by the separate location picker. Map rendering can then be composed with Flutter content. The versioned SDK constructor defaults and SurfaceView-related note are in the [Mapbox 2.29.1 source](https://github.com/mapbox/mapbox-maps-flutter/blob/v2.29.1/lib/src/map_widget.dart); Flutter describes the composition approaches and tradeoffs in its [Android platform-view documentation](https://docs.flutter.dev/platform-integration/android/platform-views).

This is one shared map configuration change. Photo selection, validation, watermarking, upload, account checks and save behavior are preserved. No dependency/native-project upgrade or backend/rules deployment is involved. No delays, map reload loops or per-screen picker workarounds were added.

## Verification

Source/APK checkpoints, recording observations, regression logs and inspected APK metadata are recorded under the ignored .usability-work-baseline/map-overlay-20261026 directory. Automated Flutter tests can check compilation and existing workflows; they do not reproduce or certify Android GPU/platform-view ordering. Final result: 361 full Flutter tests passed (one optional benchmark skipped), 212 exact-fieldtest checks passed, no analyzer errors and three existing warnings. The old experimental map-hosting warning was removed. The inspected test APK is SafePaths-Test-PhotoOverlay-20261026-v1.0.3.apk, version 1.0.3-fieldtest/code 20261028. Its test project, same signing certificate, three compiled ABIs, private-credential exclusions and preserved previous installers were verified. Full hashes are in verification.json.

## Affected-phone acceptance

Use the new SafePaths Test photo-overlay APK. Repeat each applicable case at least twice:

1. Open reporting from the map, choose Gallery, select a non-personal test image and return. The report form and selected photo must remain visible; the map must stay behind the form.
2. Repeat Gallery but cancel selection. Existing report text/photo must remain intact.
3. Repeat Camera selection and Camera cancellation where a camera is available.
4. Open Profile, Edit Profile and choose a test profile image. The profile UI must remain visible after gallery/camera return. Save and reopen to check the image persisted.
5. Return to the map. Panning, zooming, road selection and opening/reclosing another screen must work. Also check the planner/navigation map and return once from the app background.

Record phone model, Android version, source (camera/gallery), selection versus cancellation and whether the overlap reappears. Do not mark native acceptance complete solely because a build or widget test passes. Continue the resident/admin communication check after report/photo screens are usable.
