# VEIL PLAYER — PRIVACY-FIRST DIAGNOSTICS & ANOMALY SYSTEM

## 1. Overview & Core Philosophy

Veil Player is a privacy-focused, offline-first media player. The Diagnostics & Anomaly System is designed to capture technical troubleshooting data locally when Veil Player crashes or suffers playback failures.

**HARD PRIVACY GUARANTEE:**
"Diagnostic reports are generated and stored locally. Veil Player does not automatically transmit crash reports or diagnostic information."

- **No Cloud:** Zero cloud logging services (No Firebase, No Sentry, No Crashlytics, No Bugsnag).
- **No Telemetry / Analytics:** Zero user behavioral tracking or background analytics.
- **No Automatic Uploads:** Sharing is strictly user-initiated via the standard Android system share sheet.
- **No Network Access Required:** The diagnostic system functions 100% offline.

---

## 2. Architecture

```
                       VEIL PLAYER
                            │
                            ↓
                    Diagnostic Events
                            │
                            ↓
                  ┌───────────────────┐
                  │ Circular Buffer   │
                  │ ~150 events max   │
                  └───────────────────┘
                            │
                  serious issue only
                            ↓
               ┌─────────────────────────┐
               │ Report Generator        │
               │ + Privacy Sanitizer     │
               └─────────────────────────┘
                            │
                            ↓
                   App-Private Storage
                            │
                            ↓
                 Settings → Diagnostics
                            │
                   ┌────────┴────────┐
                   ↓                 ↓
              View Report       Delete Report
                   │
                   ↓
               Share Report
                   │
                   ↓
            Android Share Sheet
```

### Components
- `lib/diagnostics/diagnostic_event.dart`: Structured diagnostic event model (Category, Severity, Timestamp, Metadata).
- `lib/diagnostics/diagnostic_event_buffer.dart`: Lightweight in-memory circular buffer (capacity ~150 events).
- `lib/diagnostics/diagnostic_sanitizer.dart`: Multi-pass privacy sanitizer stripping local file paths, personal filenames, user OS usernames, IP addresses, and stack trace user paths.
- `lib/diagnostics/diagnostic_report.dart`: Structured plain text `.txt` report builder.
- `lib/diagnostics/diagnostic_storage.dart`: App-private sandbox storage with bounded retention (max 15 reports) and rate-limiting deduplication.
- `lib/diagnostics/responsiveness_monitor.dart`: Non-intrusive main-isolate stall monitor detecting UI stalls > 2500ms.
- `lib/diagnostics/diagnostic_service.dart`: Central orchestrator and Riverpod state provider.
- `lib/diagnostics/crash_handler.dart`: Interceptor for uncaught Flutter framework and Dart asynchronous errors.

---

## 3. Privacy Guarantees & Data Governance

### Captured Technical Data
- Veil Player version and build number.
- Operating System (Android version, SDK level, CPU architecture).
- Safe Device Model info (Manufacturer, Model name).
- Session ID & application state (Foreground / Background / Player Active / PiP state).
- Generic media technical metadata:
  - Container format (e.g. MKV, MP4, WEBM).
  - Video resolution (e.g. 3840x2160) & video codec (e.g. HEVC, H264).
  - Audio codec (e.g. AAC, OPUS, AC3).
  - Duration & approximate playback position.
  - Hardware decoder status (Active / Fallback).
- Recent in-memory diagnostic events.
- Sanitized exception messages and stack traces.

### EXPLICITLY EXCLUDED DATA (Hard Architectural Prohibition)
- Full media file paths (`/storage/emulated/0/...`).
- Personal directory names.
- Media filenames (`MyMovie.mkv` replaced with `<MEDIA_FILE>`).
- Thumbnails, screenshots, video frames.
- Video / audio contents or subtitle text.
- Contacts, location, account information, clipboard data.
- Device serial numbers, IMEI, Android Advertising IDs, MAC addresses, Wi-Fi SSIDs.

---

## 4. Report Retention & Deduplication

1. **Storage Location:** Private sandbox directory (`<app-doc-dir>/veil_diagnostics/reports`).
2. **Storage Limit:** Bounded to a maximum of 15 reports. Oldest reports are deleted automatically when full.
3. **Deduplication:** Repeated occurrences of identical errors within a 60-second window increment an `occurrenceCount` counter on the existing report rather than creating redundant files.

---

## 5. Sharing Mechanics

- Reports are exported only when the user explicitly opens a report and taps **Share Report**.
- Sharing uses Android's standard system share sheet via `FileProvider` with temporary `FLAG_GRANT_READ_URI_PERMISSION`.
- The user selects the destination app (Email, WhatsApp, Drive, GitHub client, etc.). Veil Player never chooses a destination.

---

## 6. Responsiveness Anomaly Semantics

- If the main Flutter isolate experiences an unprovoked stall exceeding **2500 ms** during player operations or exit:
  - Recorded as `UI_RESPONSIVENESS_ANOMALY`.
- **Note:** This is classified as a suspected responsiveness stall, NOT a confirmed system ANR (Application Not Responding), which can only be declared by the Android system OS.

---

## 7. Crash Detection Limitations

- **Uncaught Dart/Flutter Errors:** Captured reliably via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- **Native Android Uncaught Exceptions:** Captured via custom `Thread.UncaughtExceptionHandler` which records a minimal marker before delegating to default system handler.
- **OS Process Kills:** Android may terminate background applications for memory management. The system classifies unclosed sessions conservatively as *"Previous session may have ended unexpectedly"* rather than falsely claiming a crash occurred.
