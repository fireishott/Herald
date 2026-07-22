# Mimo Marching Orders - Herald v1.8.1 Point Release

**Date:** 2026-07-21
**Current version:** 1.8.0 / build 42 (HEAD `df6cf8a`)
**Target version:** 1.8.1 / build 43
**Branch:** `master`
**Remote:** `origin` = `https://github.com/fireishott/Herald.git`

---

## Cross-Cutting Rules (apply to EVERY change)

1. Bump `MARKETING_VERSION` to `1.8.1` and `CURRENT_PROJECT_VERSION` to `43` in `project.yml` (lines 81-82 AND 141-142)
2. One change = one commit = one dated CHANGELOG entry
3. Relay has **no migration framework** - ship manual `ALTER`s if schema changes
4. Swift 6 strict concurrency must stay clean (`SWIFT_STRICT_CONCURRENCY: complete`)
5. Unlock login keychain before EVERY `xcodebuild`
6. Run `xcodegen generate` after editing `project.yml`
7. Deploy relay: SSH to `fihadmin@192.168.10.101`, update files inside the `hermes-relay` container's volume, then `docker restart hermes-relay`
8. Connector is a **user-level** systemd service on `.118`: `systemctl --user restart hermes-mobile-connector.service`
9. Do NOT push to `origin/master` until all fixes land and the TestFlight build is verified

---

## Environment Block

| Thing | Value |
|------|-------|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch `master`) |
| **iOS app** | `Herald/` target, Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, iOS 18.0+ |
| **Widgets** | `HeraldWidgets/` extension, App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + SQLite; **prod relay = 192.168.10.101** (fih-docker-vm, `hermes-relay` container behind Caddy on same host); DB is SQLite `data/relay.db` (persisted volume). **NOT** the `.118:8010` stack |
| **Connector** | `connector/src/herald_connector/`; Python WS client; user-level systemd `hermes-mobile-connector.service` on `.118`; state at `~/.herald/state.json` |
| **Hermes host** | `fih-ai-host` @ `192.168.10.118`; **hard-freezes multiple times/day (OOM history)** - expect slow first-token; watchdog must not retry accepted-but-slow jobs |
| **Build machine** | MacBook Pro @ `curtisfreeman@192.168.10.121`; project dir `~/Herald/` |
| **Project gen** | XcodeGen - edit `project.yml`, run `xcodegen generate`; the `.xcodeproj` is generated |
| **Bundle / team** | `net.fihonline.herald` / `58U7UPFS53` |
| **Build output** | `~/Hermes-iOS-Builds/` on MBP |
| **GitHub remote** | `https://github.com/fireishott/Herald.git` |
| **Relay access** | `sshpass -p '<pw>' ssh fihadmin@192.168.10.101` (NO key auth yet) |
| **Connector host access** | `ssh fihadmin@192.168.10.118` |
| **Caddy** | On `192.168.10.101:443`, domain `hermes-relay.fihonline.net`, proxies to relay container |

---

## Bug Fixes

### B14: Chat Opens to Top Instead of Most Recent Messages (P0)

**Symptom:** Opening the chat screen shows the beginning of the conversation (oldest messages). User must manually scroll down to see the latest activity.

**Root cause:** `ChatScreen.swift` has no `.onAppear` or post-load scroll-to-bottom call. The only scroll triggers are reactive `.onChange` handlers:

- **Line 88-91:** `onChange(of: messages.count)` - fires when message count changes, but only when NOT streaming
- **Line 92-93:** `onChange(of: pendingMessageSentAt)` - fires when a new message is sent
- **Line 95-108:** `onChange(of: streamingMessageID)` - fires when streaming ends

When the chat screen appears with an existing conversation loaded from cache (`loadConversationIfNeeded()` at line 70), the message count doesn't change (it was already populated from cache), so the `onChange` never fires. The `scrollProxy` is set at line 673 in `.onAppear`, but no scroll action follows.

**File:** `Herald/Features/Chat/ChatScreen.swift`

**Fix:** Add a scroll-to-bottom call after the conversation loads in the `.task` block:

```swift
// Line 67-77, after the existing .task block
.task {
    chatStore.setPollingEnabled(true)
    await hostStore.refresh()
    await chatStore.loadConversationIfNeeded()
    await profileStore.loadProfiles(force: true)
    await modelStore.loadModels()
    // Scroll to most recent activity after loading
    scrollToBottom()
}
```

Also need to make `scrollToBottom()` resilient to being called before `scrollProxy` is set (it already guards `scrollProxy?` with optional chaining at line 1028, so this is safe). However, the `.onAppear` that sets `scrollProxy` (line 673) may fire after `.task` completes. Add a small delay or use `DispatchQueue.main.async`:

```swift
// After loadConversationIfNeeded completes
try? await Task.sleep(for: .milliseconds(100))
scrollToBottom()
```

**Acceptance Criteria:**
1. Open Herald - chat shows the most recent messages visible at the bottom
2. Switch away from chat tab and back - still shows most recent
3. Load a long conversation history - bottom of conversation is visible on appear

---

### B15: Add Scroll-to-Bottom Button in Chat (P1)

**Symptom:** After scrolling up in chat history, there is no quick way to return to the most recent messages. User must manually scroll all the way down.

**Root cause:** No scroll-to-bottom FAB exists. The only scroll-to-bottom mechanism is the private `scrollToBottom()` function at line 1016 which is called programmatically, never from a user-facing button.

**File:** `Herald/Features/Chat/ChatScreen.swift`

**Fix:** Add a floating "scroll to bottom" chevron button that appears when the user scrolls up from the bottom.

**Step 1 - Track scroll position.** Add a `@State` to detect when user is scrolled away from bottom:

```swift
@State private var isNearBottom = true
```

**Step 2 - Detect scroll position.** Inside `messageList` (line 630), add a GeometryReader-based anchor at the bottom of the LazyVStack to detect visibility:

```swift
// Inside LazyVStack, after the ForEach and StatusCardView
Color.clear
    .frame(height: 1)
    .id("bottomAnchor")
    .onAppear { isNearBottom = true }
    .onDisappear { isNearBottom = false }
```

**Step 3 - Overlay the button.** Add an overlay to the `ScrollViewReader` or as a `ZStack` layer:

```swift
.overlay(alignment: .bottom) {
    if !isNearBottom {
        Button {
            withAnimation(Design.Motion.standard) {
                scrollProxy?.scrollTo("bottomAnchor", anchor: .bottom)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Colors.foreground)
                .frame(width: 36, height: 36)
                .background(Design.Colors.surface3)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .padding(.bottom, Design.Spacing.lg)
        .transition(.scale.combined(with: .opacity))
    }
}
```

**Acceptance Criteria:**
1. Scroll up in chat - chevron-down button appears centered at the bottom
2. Tap the button - chat smoothly scrolls to the most recent message
3. When already at the bottom - button is hidden
4. New message arrives while scrolled up - button remains visible (user chose to read history)

---

### B16: Thinking Bubbles Disappear While Waiting for Response (P0)

**Symptom:** The thinking dots and "Thinking... Xs" timer disappear while the assistant is still processing. This causes Live Activities and the Action Center to stop updating. The stop button remains in the reply area (correct), but the visual indicator that something is happening vanishes.

**Root cause analysis:** The thinking bubbles display is gated on `message.isStreaming && message.content.isEmpty && message.toolActivities.isEmpty && message.reasoning.isEmpty` (`MessageBubble.swift:195`). The `isStreaming` flag itself is the computed property `streamingMessageID != nil` on `ChatStore` (line 54). The `streamingMessageID` is derived from `activeStreams.values.first` (line 27).

The 120-second watchdog timeout (`ChatStore.swift:34`) fires `runStreamingAttempt` returning `true` (stalled). In `runAttemptLoop` (line 183-212):
- Line 198-200: Sets `toolActivity = "Waiting for host..."` on the placeholder
- Line 202: Sleeps 30 seconds (grace period)
- Line 211: Calls `failStalledMessage` which sets `isStreaming = false`

So after 120s + 30s grace = **150 seconds**, the placeholder's `isStreaming` is set to false, which:
1. Removes the thinking bubbles (line 195 condition fails)
2. Removes the Live Activity (the chatLiveActivity tracks streaming state)
3. Stops Action Center updates

But the host may still be processing (OOM freezes cause slow first-token). The stop button remains because it's tied to the message status, not `isStreaming`.

**Two issues:**

**Issue 1:** When the watchdog sets `toolActivity = "Waiting for host..."` at line 199, this makes `message.toolActivities.isEmpty` false, which should shift the display from `streamingPlaceholder` to the tool activity pill. However, `toolActivity` (singular String?) is set but `toolActivities` (the array) is not updated. Check `MessageBubble.swift:195` - it checks `message.toolActivities.isEmpty` (the array), but the watchdog only sets `message.toolActivity` (the singular field). If the array is empty, the bubbles still show, but then the streaming flag goes false on the fail path.

**Issue 2:** After 150s the `failStalledMessage` call sets `isStreaming = false` and `status = .failed`, removing all visual indicators. On a slow host (known OOM freeze issue), 150s is not enough.

**Fix:**

**File: `Herald/Stores/ChatStore.swift`**

**Part A - Don't auto-fail while the relay still has the job.** Replace the hard timeout with a relay-aware approach. After the watchdog fires, poll the relay for job status. If the relay reports the job as still active (`status: "running"` or `status: "queued"`), extend the wait instead of failing:

```swift
// In runAttemptLoop, replace the grace period logic (lines 197-212):
// After watchdog fires (stalled == true):
if let idx = conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
    conversation?.messages[idx].toolActivity = "Waiting for host..."
}

// Poll relay for actual job status instead of blind grace period
var relayConfirmsAlive = true
for attempt in 0..<6 { // Up to 3 more minutes
    try? await Task.sleep(for: .seconds(30))
    if let msg = conversation?.messages.first(where: { $0.id == placeholderID }),
       msg.status == .delivered || !msg.content.isEmpty { return }
    
    // Check relay job status
    if let jobID = acceptedJobID {
        let jobAlive = await heraldClient.isJobActive(jobID: jobID)
        if !jobAlive {
            relayConfirmsAlive = false
            break
        }
    }
}

if !relayConfirmsAlive {
    failStalledMessage(clientMessageID: clientMessageID, placeholderID: placeholderID)
}
// If relay says alive, keep waiting — the stop button is the user's escape hatch
```

**Part B - Keep thinking bubbles visible as long as streaming.** The placeholder already shows correctly while `isStreaming` is true. Ensure the Live Activity also stays alive:

```swift
// In ChatStore, the chatLiveActivity.endActivity() call must only happen
// when isStreaming transitions to false via a TERMINAL event (.finished or .failed),
// not when the watchdog fires.
```

**Acceptance Criteria:**
1. Send a message to a slow-responding host - thinking bubbles persist for the full wait
2. Thinking timer ("Thinking... Xs") continues counting up past 120s
3. Live Activity on lock screen stays active while waiting
4. Stop button remains functional throughout
5. If the response eventually arrives after 3+ minutes, it displays correctly
6. If the user taps Stop, the bubbles and Live Activity end cleanly

---

### B17: PDF Viewer Not Fullscreen on iPad, No Close Button on iPhone (P1)

**Symptom:** When viewing a PDF attachment on iPad, it does not go fullscreen. On iPhone, there is no visible close/X button to dismiss the PDF viewer.

**Root cause:** The PDF viewer uses `QLPreviewController` wrapped in a SwiftUI `.sheet` (`MessageAttachmentsView.swift:327`):

```swift
func quickLookPreview(_ url: Binding<IdentifiableURL?>) -> some View {
    sheet(item: url) { identifiable in
        QuickLookPreview(url: identifiable.url)
            .ignoresSafeArea()
    }
}
```

- **iPad issue:** `.sheet` presents as a form sheet (smaller card) on iPad by default, not fullscreen. QuickLook needs `.fullScreenCover` or a custom presentation to fill the iPad screen.
- **iPhone issue:** The `UINavigationController` wrapping `QLPreviewController` (line 339-343) provides a nav bar with a "Done" button, but `.ignoresSafeArea()` may push the nav bar off-screen, or the sheet's drag indicator replaces the expected close affordance.

**File:** `Herald/Features/Chat/MessageAttachmentsView.swift:324-355`

**Fix:**

**Part A - Use `.fullScreenCover` instead of `.sheet`:**

```swift
func quickLookPreview(_ url: Binding<IdentifiableURL?>) -> some View {
    fullScreenCover(item: url) { identifiable in
        QuickLookPreview(url: identifiable.url)
            .ignoresSafeArea()
    }
}
```

**Part B - Add an explicit dismiss button in the QuickLook wrapper.** `QLPreviewController` inside a `UINavigationController` should provide a "Done" button, but add a SwiftUI dismiss overlay as a safety net:

```swift
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(url: url, dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: controller)
        // Add close button for iPhone
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismissTapped)
        )
        return nav
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let dismiss: DismissAction
        init(url: URL, dismiss: DismissAction) { self.url = url; self.dismiss = dismiss }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
        @objc func dismissTapped() { dismiss() }
    }
}
```

**Acceptance Criteria:**
1. Tap a PDF attachment on iPad - viewer opens fullscreen
2. Tap a PDF attachment on iPhone - viewer opens with a visible "Done" button in the nav bar
3. Tapping "Done" dismisses the viewer cleanly
4. PDF is scrollable, zoomable, and supports landscape orientation
5. Image attachments still use the existing `FullScreenImageViewer` (no regression)

---

### B18: Attachment Viewer Closes on iPhone Landscape Rotation (P1)

**Symptom:** When viewing an attachment (PDF, image, etc.) on iPhone and rotating to landscape, the attachment viewer closes and returns to the chat.

**Root cause:** The PDF viewer is presented via `.sheet` (`MessageAttachmentsView.swift:327`). On iPhone, SwiftUI sheets can be dismissed when the size class changes during rotation (compact → regular width). The image viewer uses `.fullScreenCover` which is more stable across rotations, but PDFs use `.sheet`.

Additionally, the project has **no orientation locking** — no `supportedInterfaceOrientations` override anywhere. When the system processes a rotation during a sheet presentation, the sheet may be dismissed as a side effect.

**File:** `Herald/Features/Chat/MessageAttachmentsView.swift:324-332`

**Fix:** This is resolved by B17's change from `.sheet` to `.fullScreenCover`. `.fullScreenCover` is orientation-stable and does not dismiss on rotation.

**Verification after B17 fix:**
1. Open any attachment (PDF, image) on iPhone
2. Rotate to landscape - viewer stays open
3. Rotate back to portrait - viewer stays open
4. Content re-layouts correctly in both orientations
5. Dismiss works in both orientations

---

### B19: Light Mode and Theme Selector Do Not Work (P0)

**Symptom:** Selecting "Light" or "System" in the appearance picker (Settings > Appearance) has no visible effect. The app always appears dark.

**Root cause — two disconnected systems:**

**Issue 1: `Design.Colors` uses hardcoded dark-mode constants, never consults ThemeManager.**

`Herald/Core/Design.swift:29-54` defines `Design.Colors` as static `let` constants with hardcoded dark hex values:
```swift
enum Colors {
    static let background = Color(hex: 0x16181A)      // dark
    static let foreground = Color(hex: 0xC1C0B6)      // light-on-dark
    static let secondaryForeground = Color(hex: 0x8D8D85) // grey
    // ... all hardcoded dark colors
}
```

The entire app uses `Design.Colors.*` for all styling. `ThemeManager` computes correct light/dark palettes via `ThemePreset.colors(for:)` (Theme.swift:138-140), and the Settings UI writes to `ThemeManager.colorSchemePreference` (SettingsScreen.swift:452-456), but **nothing reads `ThemeManager.currentPalette` to drive `Design.Colors`**.

**Issue 2: No `.preferredColorScheme()` on the root view.**

`HeraldApp.body` (`AppEntry.swift:113-140`) applies 15+ `.environment()` modifiers but never calls `.preferredColorScheme()`. Without this, SwiftUI always uses the system color scheme for system chrome (status bar, keyboard, alerts, sheets). Even if `Design.Colors` were dynamic, the system elements would not respect the in-app preference.

**Fix — two parts:**

**Part A - Wire `Design.Colors` to `ThemeManager`.** Convert `Design.Colors` from static constants to dynamic computed properties that read from `ThemeManager.shared`:

**File: `Herald/Core/Design.swift`**

```swift
enum Colors {
    private static var palette: ThemePalette {
        ThemeManager.shared.currentPalette
    }

    static var background: Color { palette.background }
    static var foreground: Color { palette.foreground }
    static var secondaryForeground: Color { palette.secondaryForeground }
    static var surface: Color { palette.surface }
    static var divider: Color { palette.divider }

    // Keep derived surfaces, borders, signals as relative to the palette
    static var backgroundRaised: Color { palette.surface }
    static var surface2: Color { palette.surface.opacity(1.6) }
    static var surface3: Color { palette.surface.opacity(2.8) }
    static var border: Color { palette.divider.opacity(1.5) }
    static var borderStrong: Color { palette.divider.opacity(2.75) }

    // Semantic colors stay fixed (they work in both light and dark)
    static let success = Color(hex: 0x00C275)
    static let warning = Color(hex: 0xCF9A2F)
    // ... keep other semantic colors as static let
}
```

**Part B - Update `ThemeManager.currentScheme` from the system and apply `.preferredColorScheme`.**

**File: `Herald/Core/ThemeManager.swift`**

The `currentScheme` property (line 10) defaults to `.dark` and is never updated from the system. It needs to track the system scheme and react to preference changes:

```swift
// ThemeManager already has resolvedColorScheme(for:) at line 12.
// Make currentScheme a computed property that resolves against the stored preference.
// The system scheme must be injected from the SwiftUI environment.
var systemScheme: ColorScheme = .dark

var currentScheme: ColorScheme {
    resolvedColorScheme(for: systemScheme)
}
```

**File: `Herald/AppEntry.swift`**

Add `.preferredColorScheme()` and inject the system scheme into ThemeManager:

```swift
// In HeraldApp.body, around line 114-116:
var body: some Scene {
    WindowGroup {
        AppRootView()
            // ... existing .environment() calls ...
            .preferredColorScheme(container.themeManager.resolvedScheme)
            .onAppear {
                // Inject initial system scheme
            }
    }
}
```

A cleaner approach: create a small wrapper view that reads `@Environment(\.colorScheme)` and feeds it into `ThemeManager.systemScheme`:

```swift
struct ThemeAwareRootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        AppRootView()
            .onChange(of: systemScheme, initial: true) { _, newScheme in
                themeManager.systemScheme = newScheme
            }
            .preferredColorScheme(
                themeManager.colorSchemePreference == .system
                    ? nil  // follow system
                    : themeManager.colorSchemePreference == .light ? .light : .dark
            )
    }
}
```

**Part C - Verify `ThemePalette` light colors.** Theme.swift lines 103-136 show that only `.herald` and `.mono` presets have explicit light palettes; all others use `synthesizeLight(from:)` which returns generic `Color(hex: 0xF5F5F5)`. This is acceptable for v1.8.1 but light mode quality on the non-herald presets will be basic.

**Acceptance Criteria:**
1. Settings > Appearance > Light: app background becomes light, text becomes dark, all UI elements are legible
2. Settings > Appearance > Dark: app stays dark (current behavior)
3. Settings > Appearance > System: app follows iOS system appearance setting
4. Keyboard, status bar, system alerts, and share sheets match the selected scheme
5. Theme preset selector (Herald, Midnight, Ember, Mono, Cyberpunk, Slate) works in both light and dark
6. Chat bubbles, sidebar, settings, onboarding all use the correct palette
7. App relaunch preserves the theme choice

---

### B20: Save-to-Files Keyboard Conflict on iPad (P1)

**Symptom:** When trying to save an attachment to Files and renaming it, the keyboard opens on iPad and its appearance causes the save window to close.

**Root cause:** This is an iOS system interaction bug. When the "Save to Files" modal (`UIDocumentPickerViewController` or `UIActivityViewController`) presents its rename field, the keyboard animation on iPad can resize the hosting view. If the share sheet was presented from a SwiftUI `.sheet` or popover, the keyboard's frame change can cause the hosting presentation to dismiss.

**File:** `Herald/Features/Chat/MessageAttachmentsView.swift`

The current share sheet is presented via `UIActivityViewController` (lines 316-322). On iPad, `UIActivityViewController` requires `sourceView`/`sourceRect` or `barButtonItem` for its popover, or it crashes. If it defaults to a popover and the keyboard changes the layout, the popover may be dismissed.

**Fix:** Present the activity controller with explicit popover configuration and prevent keyboard-driven dismissal:

```swift
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let sourceRect: CGRect

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // On iPad, configure the popover to anchor to the source and not dismiss on keyboard
        if let popover = controller.popoverPresentationController {
            popover.sourceView = context.coordinator.sourceView
            popover.sourceRect = sourceRect
            popover.permittedArrowDirections = [.up, .down]
        }
        return controller
    }
    // ...
}
```

Alternatively, use SwiftUI's `ShareLink` (available iOS 16+) which handles iPad presentation correctly:

```swift
ShareLink(item: fileURL) {
    Label("Share", systemImage: "square.and.arrow.up")
}
```

For the "Save to Files" specifically, use `fileExporter` modifier which handles keyboard presentation correctly:

```swift
.fileExporter(
    isPresented: $showFileExporter,
    document: attachmentDocument,
    contentType: .data,
    defaultFilename: attachment.fileName
) { result in
    // handle result
}
```

**Acceptance Criteria:**
1. Long-press an attachment > Save to Files on iPad
2. The save dialog opens and allows renaming
3. Keyboard appears without dismissing the save dialog
4. File saves successfully with the custom name
5. Same flow works on iPhone without issue

---

### B21: Attachment Size Limit Too Small for Multiple iPhone Photos (P1)

**Symptom:** Cannot attach multiple photos from iPhone to a single message. iPhone photos are large (12MP HEIC = 2-5MB each) and the current limits are too restrictive.

**Root cause:** `PendingAttachment.swift:23-24`:
```swift
static let maxFileSize = 350 * 1024        // 350 KB per attachment
static let maxAttachmentsPerMessage = 4     // max 4 attachments
```

The 350KB limit after JPEG compression (max 768px, quality 0.5 at line 48-73) is extremely tight. iPhone 15 Pro photos at 48MP can't compress to 350KB at readable quality. The progressive quality reduction (lines 64-72) drops to 0.1 quality which destroys image readability, and if still over 350KB, returns `nil` (line 73) with **no error message** to the user.

The 1MB API body limit (line 20-22) is the real constraint. With base64 encoding overhead (~33%), 350KB binary = ~470KB base64. Four attachments = 1.88MB base64 which exceeds the 1MB body limit.

**Fix — two changes:**

**Part A - Increase per-attachment limit and adjust downscaling:**

**File: `Herald/Models/PendingAttachment.swift`**

```swift
// Increase max dimension for better readability
let maxDimension: CGFloat = 1024  // was 768

// Increase per-file limit - the relay body limit (1MB) is the real cap
static let maxFileSize = 800 * 1024  // 800 KB (was 350 KB)
static let maxAttachmentsPerMessage = 5  // was 4
```

**Part B - Increase the relay's request body limit:**

**File: `relay/app/main.py`** — find the Starlette/FastAPI request body limit and increase it. Default FastAPI limit is typically 1MB. Increase to 5MB:

```python
# In the FastAPI app creation or middleware
app = FastAPI(
    title="Herald Relay",
    # ...
)

# Increase body limit for attachments
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware

@app.middleware("http")
async def increase_body_limit(request, call_next):
    # Allow up to 5MB for attachment messages
    return await call_next(request)
```

Or set `--limit-request-line` / body size on the ASGI server (uvicorn):
```
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--limit-max-request-size", "5242880"]
```

**Part C - Show error feedback when attachment is too large:**

**File: `Herald/Features/Chat/ChatScreen.swift`** — in `handleAttachmentResult` (around line 816-828), when `PendingAttachment.image()` returns nil, show a toast/alert:

```swift
if attachment == nil {
    appendSystemMessage("Attachment too large. Try a smaller file or fewer photos.")
}
```

**Acceptance Criteria:**
1. Attach 3 iPhone photos to a single message - all attach successfully
2. Photos are readable (not heavily compressed artifacts)
3. If a photo is truly too large after downscaling, user sees an error message
4. Relay accepts the larger payload without 413 errors
5. Attachment thumbnails display correctly in the composer

---

### B22: Image Attachments Show Spinning Circles (Intermittent) (P2)

**Symptom:** Image attachments sometimes display indefinite spinning circles (loading indicators) instead of the actual image.

**Root cause:** `MessageAttachmentsView.swift:149-153` shows a `ProgressView()` spinner when both `fullImage` and `thumbnail` are nil. The full image is loaded via `attachmentService.image(for:)` in a `.task` block (line 141-146). `AttachmentService.swift` has:
- In-memory `NSCache` with 32MB limit (line 28) — no disk persistence
- Network fetch with token-based auth (lines 54-70)
- On 401, it attempts one token refresh (line 63) then retries

Intermittent failures can occur when:
1. **Token expiry:** The access token expires between thumbnail load and full-image load. The retry logic handles one 401, but if the refresh itself fails, the image stays as a spinner.
2. **NSCache eviction:** With a 32MB cache limit, loading many images in a conversation evicts earlier ones. When scrolling back, those images must be re-fetched, and if the network request fails, they show spinners.
3. **Race condition in inflight deduplication:** `AttachmentService.swift:18` has an `inflight` dictionary. If two views request the same attachment simultaneously and the first fails, both get the failure.
4. **No retry on failure:** `AuthenticatedAsyncImage.swift` has no retry logic — once the phase is `.failure`, the image stays failed.

**Fix — add retry and disk caching:**

**File: `Herald/Services/Support/AttachmentService.swift`**

**Part A - Add disk cache.** Store fetched images on disk so they survive app restart and NSCache eviction:

```swift
private func diskCachePath(for key: String) -> URL {
    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("HeraldAttachments", isDirectory: true)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    return cacheDir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
}

// In data(for:), before network fetch, check disk cache:
if let diskData = try? Data(contentsOf: diskCachePath(for: cacheKey)) {
    cache.setObject(diskData as NSData, forKey: cacheKey as NSString)
    return diskData
}

// After successful network fetch, write to disk cache:
try? fetchedData.write(to: diskCachePath(for: cacheKey))
```

**Part B - Add retry in AttachmentImageView.** 

**File: `Herald/Features/Chat/MessageAttachmentsView.swift`**

In `AttachmentImageView`, add a retry mechanism:

```swift
@State private var loadAttempt = 0
private let maxRetries = 2

// In the .task block:
.task(id: loadAttempt) {
    guard fullImage == nil, loadAttempt <= maxRetries else { return }
    // ... existing load logic ...
    if fullImage == nil && loadAttempt < maxRetries {
        try? await Task.sleep(for: .seconds(2))
        loadAttempt += 1
    }
}
```

**Acceptance Criteria:**
1. Send a message with 3 image attachments - all images load without spinners
2. Scroll through a long conversation with many images - no persistent spinners
3. Force-quit and reopen app - previously loaded images load from disk cache (no spinner)
4. If network is truly unavailable, images show a placeholder icon (not infinite spinner)

---

## Relay Deployment Procedure

Before deploying iOS changes, deploy any relay changes first.

### Current Relay Topology (VERIFIED 2026-07-20)

- **Prod relay:** `192.168.10.101` (fih-docker-vm)
- **Container:** `hermes-relay` behind `caddy` container on same host
- **DB:** SQLite at `data/relay.db` (persisted volume), NOT Postgres
- **Access:** `sshpass -p '<pw>' ssh fihadmin@192.168.10.101`
- **Connector** on `.118`: state `~/.herald/state.json`, systemd user service

### Relay Deploy Steps

```bash
# 1. SSH to relay host
ssh fihadmin@192.168.10.101

# 2. Back up current relay DB
docker exec hermes-relay cp /data/relay.db /data/relay.db.bak-$(date +%Y%m%d)

# 3. Copy updated relay code from dev machine to host
# (from the Herald repo on the dev machine)
scp -r /Users/curtisfreeman/Herald/relay/ fihadmin@192.168.10.101:/tmp/relay-update/

# 4. On the host, update the relay container's code
# The exact method depends on how the container mounts the code:
# If bind-mounted:
cp -r /tmp/relay-update/relay/app/* /path/to/hermes-relay/app/

# If Dockerfile-based:
cd /path/to/hermes-relay && docker compose up -d --build

# 5. Verify relay health
curl -s http://localhost:8000/v1/health

# 6. Restart connector on .118
ssh fihadmin@192.168.10.118
systemctl --user restart hermes-mobile-connector.service
systemctl --user status hermes-mobile-connector.service
```

### APNs Environment Handling

The relay `.env` on `.101` controls APNs routing:

| Build Type | `APNS_ENVIRONMENT` Value | When to Set |
|-----------|------------------------|-------------|
| Sideloaded (Xcode direct install) | `development` | Default for dev builds |
| TestFlight / App Store | `production` | **Before** uploading TestFlight build |

**Per-registration routing (implemented in 1.8.0 B7/B8):** The relay now stores `push_environment` per registration. Verify this works by checking the `push_registrations` table after both dev and TestFlight devices register.

---

## TestFlight Build & Upload Procedure

### Keys & IDs

| What | Value | Location |
|---|---|---|
| ASC key (upload) | `32NT26772F` | `~/.appstoreconnect/private_keys/AuthKey_32NT26772F.p8` |
| ASC key (admin) | `UQWH2GWTLU` | `~/.appstoreconnect/private_keys/AuthKey_UQWH2GWTLU.p8` |
| APNs key (do NOT use for upload) | `LH5GM8356P` | `~/.appstoreconnect/private_keys/AuthKey_LH5GM8356P.p8` |
| Issuer ID | `69a6de93-5191-47e3-e053-5b8c7c11a4d1` | — |
| Team | `58U7UPFS53` | — |
| Bundle ID | `net.fihonline.herald` | — |
| App Store Connect app ID | `6792659019` | — |
| Internal beta group ID | `d852fc3e-865e-428d-a4d6-a11011854942` | — |
| MBP | `curtisfreeman@192.168.10.121` | — |
| Project dir | `~/Herald/` | MBP |
| Build output | `~/Hermes-iOS-Builds/` | MBP |
| ExportOptions.plist | `~/Hermes-iOS-Builds/exports/ExportOptions.plist` | MBP |
| iPhone UDID | `8BE18B66-1D74-5495-82FA-F8A74B505947` | — |
| iPad UDID | `A1AB3152-5CA0-5E28-9431-92BF4AC3312C` | — |

### Current Testers

Curtis Freeman (`djkurttsaynomore@gmail.com`), Mini Me (`curtisdate@icloud.com`), Mark Davis (`markbdvt@gmail.com`)

### Step-by-Step TestFlight Pipeline

#### 1. Version Bump

On the MBP (or push from dev machine and pull on MBP):

```bash
cd ~/Herald
git pull origin master

# Verify version is 1.8.1 / build 43
grep -n 'MARKETING_VERSION\|CURRENT_PROJECT_VERSION' project.yml
# Should show: 1.8.1 and 43 in 4 places (2 per target)

# Regenerate Xcode project
xcodegen generate
```

#### 2. Pre-Build: Switch Relay APNs to Production

```bash
# SSH to relay host
ssh fihadmin@192.168.10.101

# Edit .env to production for TestFlight tokens
# Find the hermes-relay .env and change:
# APNS_ENVIRONMENT=production

# Restart relay
docker restart hermes-relay

# Verify
curl -s http://localhost:8000/v1/health
```

#### 3. Build, Archive, Export (ONE SSH call)

**Critical:** The entire build must happen in a single SSH session because the keychain re-locks between sessions.

```bash
ssh curtisfreeman@192.168.10.121 << 'ENDSSH'
set -e
cd ~/Herald

# Unlock keychain (REQUIRED before every xcodebuild)
security unlock-keychain -p "$LOGIN_KEYCHAIN_PW" ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_KEYCHAIN_PW" ~/Library/Keychains/login.keychain-db

# Regenerate project
xcodegen generate

# Clean build folder
xcodebuild clean -scheme Herald -configuration Release

# Strip entitlements for TestFlight (paid team lacks HealthKit/App Groups)
cp Herald/HermesMobile.entitlements Herald/HermesMobile.entitlements.backup
cat > Herald/HermesMobile.entitlements << 'ENTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
ENTEOF

# Archive
ARCHIVE_PATH=~/Hermes-iOS-Builds/Herald-1.8.1.xcarchive
xcodebuild archive \
    -scheme Herald \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=iOS' \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=58U7UPFS53

# Export IPA
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist ~/Hermes-iOS-Builds/exports/ExportOptions.plist \
    -exportPath ~/Hermes-iOS-Builds/export-1.8.1/

# Restore entitlements
cp Herald/HermesMobile.entitlements.backup Herald/HermesMobile.entitlements
rm Herald/HermesMobile.entitlements.backup

echo "BUILD COMPLETE: ~/Hermes-iOS-Builds/export-1.8.1/"
ls -la ~/Hermes-iOS-Builds/export-1.8.1/*.ipa
ENDSSH
```

#### 4. Upload to App Store Connect

```bash
ssh curtisfreeman@192.168.10.121 << 'ENDSSH'
xcrun altool --upload-app \
    --type ios \
    --file ~/Hermes-iOS-Builds/export-1.8.1/Herald.ipa \
    --apiKey 32NT26772F \
    --apiIssuer 69a6de93-5191-47e3-e053-5b8c7c11a4d1
ENDSSH
```

#### 5. Verify Processing in App Store Connect

```bash
# Poll build processing status using admin key
curl -s \
  -H "Authorization: Bearer $(python3 -c "
import jwt, time
key = open('$HOME/.appstoreconnect/private_keys/AuthKey_UQWH2GWTLU.p8').read()
payload = {
    'iss': '69a6de93-5191-47e3-e053-5b8c7c11a4d1',
    'iat': int(time.time()),
    'exp': int(time.time()) + 1200,
    'aud': 'appstoreconnect-v1'
}
print(jwt.encode(payload, key, algorithm='ES256', headers={'kid': 'UQWH2GWTLU'}))
")" \
  "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6792659019&sort=-uploadedDate&limit=1" \
  | python3 -m json.tool | grep -E '"version"|"processingState"'

# Expected: processingState = "VALID"
# If "PROCESSING", wait and retry in 5 minutes
```

#### 6. Add Build to Internal Testing Group

Once processing shows `[VALID]`:
1. Go to App Store Connect > Herald > TestFlight
2. Find the new build (1.8.1, build 43)
3. Add to internal testing group (ID: `d852fc3e-865e-428d-a4d6-a11011854942`)
4. Testers will receive TestFlight notification

#### 7. Post-Upload: Verify APNs

After TestFlight build is installed:
1. Open Herald on TestFlight device
2. Verify push registration succeeds (check relay logs)
3. Send a test message and verify push notification arrives on lock screen
4. If push fails, check `push_registrations` table for correct `push_environment = 'production'`

### Critical Rules Reminder

- **One SSH call** for archive + export (keychain re-locks between sessions)
- **Strip entitlements** before build, restore after
- **Don't use APNs key** (`LH5GM8356P`) for upload — use upload key `32NT26772F`
- **Don't set CODE_SIGN_IDENTITY** with automatic signing
- TestFlight builds **lose HealthKit/App Groups** due to entitlement stripping

---

## Commit Order

| Order | Fix | Component | Deploy |
|-------|-----|-----------|--------|
| 1 | B14: Chat scroll-to-bottom on load | iOS (`ChatScreen.swift`) | App rebuild |
| 2 | B15: Scroll-to-bottom FAB button | iOS (`ChatScreen.swift`) | App rebuild |
| 3 | B16: Thinking bubbles persist until turn done | iOS (`ChatStore.swift`, `MessageBubble.swift`) | App rebuild |
| 4 | B17: PDF viewer fullscreen + close button | iOS (`MessageAttachmentsView.swift`) | App rebuild |
| 5 | B18: Attachment viewer rotation stability | iOS (resolved by B17) | — |
| 6 | B19: Light mode + theme selector | iOS (`Design.swift`, `ThemeManager.swift`, `AppEntry.swift`) | App rebuild |
| 7 | B20: Save-to-files keyboard on iPad | iOS (`MessageAttachmentsView.swift`) | App rebuild |
| 8 | B21: Attachment size limit increase | iOS (`PendingAttachment.swift`, `ChatScreen.swift`) + Relay (body limit) | App rebuild + relay restart |
| 9 | B22: Image spinner retry + disk cache | iOS (`AttachmentService.swift`, `MessageAttachmentsView.swift`) | App rebuild |
| 10 | Version bump to 1.8.1 / build 43 | `project.yml` | xcodegen + build |

---

## CHANGELOG Entry

After all fixes land, add this block at the top of `CHANGELOG.md` (after the `# Changelog` header, before `## [1.8.0]`):

```markdown
## [1.8.1] - 2026-07-XX

### Fix: Chat opens to most recent messages (B14)

- **Scroll-to-bottom on load** (`ChatScreen.swift`): Chat now scrolls to the most recent message when the screen appears, instead of showing the top of conversation history.

### Added: Scroll-to-bottom button (B15)

- **Floating chevron button** (`ChatScreen.swift`): When scrolled up in chat, a chevron-down button appears at the bottom center to quickly return to the latest messages.

### Fix: Thinking bubbles persist until response completes (B16)

- **Extended watchdog tolerance** (`ChatStore.swift`): Thinking dots and "Thinking... Xs" timer now persist as long as the relay reports the job is still active, instead of disappearing after 120s. Supports the known slow-host scenario.
- **Live Activity stays alive** (`ChatStore.swift`): Lock screen Live Activity no longer ends prematurely on watchdog timeout.

### Fix: PDF viewer fullscreen and close button (B17/B18)

- **Fullscreen presentation** (`MessageAttachmentsView.swift`): PDF viewer now uses `.fullScreenCover` instead of `.sheet`, filling the iPad screen and preventing rotation-triggered dismissals on iPhone.
- **Explicit close button** (`MessageAttachmentsView.swift`): "Done" button always visible in the PDF viewer navigation bar on both iPhone and iPad.

### Fix: Light mode and theme selector (B19)

- **Dynamic Design.Colors** (`Design.swift`): All `Design.Colors` properties now read from `ThemeManager`'s active palette instead of hardcoded dark hex values.
- **preferredColorScheme applied** (`AppEntry.swift`): Root view now applies `.preferredColorScheme` so system chrome (status bar, keyboard, alerts) matches the user's in-app theme selection.
- **System/Light/Dark all functional** (`ThemeManager.swift`): Appearance selector in Settings now correctly switches between system, light, and dark modes.

### Fix: Save-to-files keyboard conflict on iPad (B20)

- **Stable share presentation** (`MessageAttachmentsView.swift`): Share/save dialogs use popover anchoring on iPad to prevent keyboard appearance from dismissing the dialog.

### Fix: Attachment size increased for iPhone photos (B21)

- **Larger per-attachment limit** (`PendingAttachment.swift`): Increased from 350KB to 800KB, with max dimension from 768px to 1024px.
- **5 attachments per message** (`PendingAttachment.swift`): Increased from 4 to 5.
- **User feedback on failure** (`ChatScreen.swift`): System message shown when an attachment exceeds the size limit.
- **Relay body limit increased** (`relay/app/main.py`): Request body limit raised to 5MB to support larger payloads.

### Fix: Image attachment loading reliability (B22)

- **Disk cache** (`AttachmentService.swift`): Fetched attachment images are now cached on disk, surviving app restart and memory pressure.
- **Automatic retry** (`MessageAttachmentsView.swift`): Failed image loads retry up to 2 times with a 2-second delay.
```

---

## GitHub Release & Tag Procedure

After all commits land and TestFlight build is verified:

### 1. Tag the release

```bash
cd /Users/curtisfreeman/Herald
git tag -a v1.8.1 -m "Herald v1.8.1 - chat scroll, thinking persistence, light mode, attachment improvements"
git push origin v1.8.1
```

### 2. Push all commits

```bash
git push origin master
```

### 3. Create GitHub release

```bash
gh release create v1.8.1 \
  --title "Herald v1.8.1" \
  --notes "$(cat <<'EOF'
## Herald v1.8.1 - UX Polish & Reliability

### Critical Fixes
- **Chat scroll position** (B14): Chat now opens to the most recent messages instead of the top
- **Thinking indicator persistence** (B16): Thinking dots stay alive until the response completes, even on slow hosts (3+ minutes)
- **Light mode** (B19): System/Light/Dark theme selector now works correctly across the entire app

### UI Improvements
- **Scroll-to-bottom button** (B15): Floating chevron to quickly return to latest messages
- **PDF viewer** (B17/B18): Fullscreen on iPad, close button on iPhone, rotation-stable
- **Save-to-files** (B20): Keyboard no longer dismisses the save dialog on iPad

### Attachments
- **Larger photos** (B21): Increased attachment size limit for iPhone photos (800KB, up to 5 per message)
- **Loading reliability** (B22): Disk caching and auto-retry for image attachments

**Full Changelog:** See CHANGELOG.md
EOF
)"
```

---

## Post-Ship Verification Checklist

### Chat & Scroll
- [ ] Open Herald with existing conversation - most recent messages visible at bottom
- [ ] Scroll up in chat - chevron-down button appears
- [ ] Tap chevron - smoothly scrolls to bottom
- [ ] At bottom - chevron is hidden

### Thinking Indicator
- [ ] Send a message - thinking dots appear
- [ ] Wait 2+ minutes on slow host - dots persist, timer keeps counting
- [ ] Live Activity on lock screen stays active during wait
- [ ] Stop button works to cancel
- [ ] Response eventually arrives - dots disappear, response displays

### PDF & Attachments
- [ ] Tap PDF on iPad - opens fullscreen
- [ ] Tap PDF on iPhone - close/Done button visible
- [ ] Rotate iPhone while viewing PDF - viewer stays open
- [ ] Rotate iPhone while viewing image - viewer stays open

### Theme
- [ ] Settings > Light - entire app switches to light background/dark text
- [ ] Settings > Dark - entire app switches back to dark
- [ ] Settings > System - follows iOS system setting
- [ ] Keyboard, status bar, alerts match selected theme
- [ ] Theme persists across app relaunch

### Attachments
- [ ] Attach 3 iPhone photos to one message - all attach and send
- [ ] Images are readable quality (not over-compressed)
- [ ] Scroll through image-heavy conversation - no persistent spinners
- [ ] Force-quit and reopen - images load from cache (no spinners)
- [ ] Save attachment to Files on iPad - keyboard doesn't dismiss save dialog

### Regression
- [ ] Streaming works end-to-end (text, reasoning, tool activity, terminal)
- [ ] Push notifications arrive on both devices
- [ ] Model picker shows active model on iPad
- [ ] Notes workspace opens and functions
- [ ] Talk mode doesn't crash
- [ ] Onboarding shows only Tailscale + Self-Hosted Relay

### TestFlight Specific
- [ ] TestFlight build installs on all tester devices
- [ ] Push notifications work on TestFlight (production APNs)
- [ ] Health permissions show "not available in this build" (expected - entitlements stripped)
