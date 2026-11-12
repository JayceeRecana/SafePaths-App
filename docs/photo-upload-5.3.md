# Section 5.3: photo upload handling

## Implemented

- The picker no longer explicitly converts/resizes the selected file before validation. Returned image bytes must have a JPEG or PNG signature, be readable by the matching decoder, and be no larger than 10 MB. HEIC/GIF/WebP and malformed inputs receive a clear JPG/PNG message rather than being silently processed as another format.
- Image headers are inspected before full decoding. Images above 16 megapixels or with a side above 20,000 pixels are rejected to limit memory use. Only the first frame is decoded. Processing runs in an isolate; normalized photos fit within 1600 pixels before native watermarking and final JPEG uploads fit within 600 pixels at quality 70. Extremely thin images retain at least one pixel in each dimension.
- The form displays **Processing photo**, **Uploading photo: N%**, and **Saving report** as separate stages. Percentages come from Firebase Storage bytes transferred/total bytes. Saving remains indeterminate and never appears as a completed report just because the photo reached 100%.
- A successful photo URL is retained for retries of the same form/photo/account. If report saving fails or its response is lost, retry skips photo compression/upload. If only URL retrieval fails after Storage completed, the uploader retains the completed object and retries URL retrieval. Removing/replacing the photo invalidates the cache; account identity is part of the cache key.
- Duplicate submission taps are blocked. Leaving the screen cancels the upload task where possible, disconnects progress listeners and prevents a later transition into report saving. A report request already sent to the backend cannot be canceled by closing the screen; the existing server request receipts protect retries against duplicate saves.
- Form values used for saving are captured before asynchronous uploading. Temporary normalized/watermarked photos created by this form are cleaned up. User originals are not deleted. Report-photo download URLs are no longer written to debug logs by the upload UI.
- Preview dimensions remain bounded and decode errors show a fallback. The preview badge now says “Photo attached”; attachment/watermarking does not claim that an administrator verified the evidence. Photo moderation (section 4.2) remains deferred.

## Validation

- Automated regressions cover JPEG/PNG acceptance, unsupported/damaged/oversized inputs, large declared dimensions, portrait normalization, one-pixel aspect ratios, reuse after a failed save, account/photo changes, upload failure, duplicate taps, leaving the screen, no-photo reports, and readable progress at narrow widths with large text.
- Android smoke probe: `scripts/photo_upload_android_probe.dart`, explicitly launched on the Pixel 9 emulator. Five real native codec/watermark/file cases passed (1x1, 40x20, 2000x500, 500x2000, 2000x40), along with progress display and retry reuse using simulated upload/save callbacks. It does not submit reports or invoke cloud uploads.
- The emulator initially had insufficient installation space; Flutter reinstalled the probe app. The first Flutter install removed/reinstalled the emulator?s previous app copy after a low-space failure; any prior local app data on that emulator may have been cleared. Later removal of the probe binary explicitly retained its data. A smaller normal-app profile build is used for restoration because the emulator cannot fit a debug reinstall. No physical device or cloud report data was deleted. This probe is not a release entrypoint.

## Remaining acceptance and rollout

1. Verify actual camera/gallery selection and permission denial on physical Android devices, especially lower-memory devices and vendor-specific galleries.
2. With a verified staging account, test real Firebase Storage upload percentages, link retrieval and report saving on slow internet. Interrupt networking during upload and during save; verify recovery without duplicate uploads/reports and without false success.
3. Test backgrounding/returning and process termination. The photo cache is per live form; it is not a persistent offline draft or a resumable upload queue after process death.
4. Deploy the coordinated backend, rules and matching app described in `reliability-rollout.md`; section 5.1 also requires verified accounts. Do not deploy restrictive rules alone while testers still use old clients.
5. Use a properly signed release build for resident distribution. A debug APK is for review/testing only. No production deployment or tester distribution was performed by these code/test changes.

Reference: [Firebase Storage upload progress and cancellation](https://firebase.google.com/docs/storage/flutter/upload-files).

Final automated results: **158 Flutter tests and 13 backend unit/parity tests passed**. Targeted analysis of the five upload files reported **no issues**. The Android production-flavor debug APK builds successfully. Native Android smoke checks use simulated upload/save callbacks, so actual Storage transfer, live report saving, camera/gallery permissions and interrupted-network acceptance are not claimed complete.

Review artifact: `build/app/outputs/flutter-apk/SafePaths-review-universal-debug.apk` (universal debug build). A production rollout decision is requested separately because the tightened backend rules are incompatible with older report-submission clients.

Rollout decision: the team wants to keep fixing remaining issues before another review build or production rollout. **No production deployment or tester distribution is authorized at this stage.** The APKs already produced were for compilation/emulator verification. The normal app was successfully restored to the emulator using `app-production-profile.apk`; the universal debug review artifact remains available locally.
