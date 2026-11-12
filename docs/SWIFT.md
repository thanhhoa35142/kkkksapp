# Pickhour — Swift conventions (iOS 17+)

Best practices từ WWDC24/25 + Swift 6.2, áp dụng cho codebase này. Nguồn: Apple "Explore concurrency in SwiftUI" (WWDC25/266), "Migrate your app to Swift 6" (WWDC24/10169), Swift.org migration guide.

## State & observation

- **`@Observable` macro, KHÔNG `ObservableObject`/`@Published`/`@StateObject`/`@ObservedObject`** — iOS 17+ dùng Observation framework: tracking theo từng property, view chỉ redraw khi property nó đọc thay đổi.
- ViewModel pattern: `@Observable @MainActor final class` + `import Observation`. `@MainActor` luôn bật — UI state thuộc main thread.
- View **tạo** instance giữ `@State private var vm = MyViewModel()`; view **nhận** từ parent dùng `@Bindable var vm` khi cần binding (`$vm.foo`), hoặc plain property khi read-only.
- `APIClient` đã là `actor` → Sendable tự nhiên, ViewModel gọi `await` bình thường. Shared services inject qua `.environment(AppConfig.apiClient)` hoặc singleton `AppConfig`.
- `DeepLinkRouter`/`PushManager`/`EventQueue`: đổi `ObservableObject` → `@Observable` khi refactor (PushManager/DeepLinkRouter hiện dùng ObservableObject — migrate khi đụng vào).

## Concurrency

- **`.task { }` / `.task(id:)`** cho mọi async do view trigger — tự cancel khi view disappear hoặc id đổi. Không `Task {}` trần trong body/onAppear nếu không manage.
- Debounce/search: `.task(id: query)` + `try await Task.sleep(for:)` rồi check `Task.isCancelled` — **không** `try?` (nuốt cancellation).
- `deinit` KHÔNG reliable cho cleanup trong SwiftUI (sheet/navigation) → cancel work trong `.onDisappear`.
- Actor cho I/O/background (`APIClient`, `EventQueue` đã đúng). `@Observable @MainActor` class chỉ giữ UI state — tách rõ 2 layer, chỉ immutable Sendable structs (models đã là Codable structs) đi qua boundary.
- Swift 6.2 "approachable concurrency": `nonisolated async` chạy trên caller's actor → nonisolated function nặng phải đánh `@concurrent` hoặc `Task.detached`, nếu không sẽ chạy trên main thread gây hang.
- Swift 6 language mode: bật **per-target**, bắt đầu bằng complete concurrency checking (warnings) ở Swift 5 mode → fix warnings → mới bật Swift 6 mode. Đừng refactor lớn + bật mode cùng lúc.

## SwiftUI patterns

- `NavigationStack` + `navigationDestination` cho detail; programmatic deep link (notification tap) qua `DeepLinkRouter.pendingSpotID` → consume 1 lần.
- `.searchable` cho search; `ContentUnavailableView` cho empty/error (đã có `EmptyStateView` wrap).
- Format: `Text(date, style:)`, `FormatStyle` — không tự viết DateFormatter trừ khi cần style đặc biệt.
- Animation: `.animation(_:value:)` scoped, tôn trọng Reduce Motion (`@Environment(\.accessibilityReduceMotion)`).
- List nặng → `LazyVStack`/`List` + `.task` per-row, không load-all.

## Data & persistence

- Keychain (`KeychainStore`) cho secrets/device ID/APNs token — đã có.
- Favorites/cache local → **SwiftData** (native iOS 17, spec cho phép) thay vì tự viết SQLite.
- `EventQueue` file-based đã đúng — giữ.

## Cấm / tránh

- Không `ObservableObject`, `@Published`, `Combine` cho state mới.
- Không third-party UI lib (đã chốt native-only).
- Không force-unwrap, không `try!`, không `fatalError` trong production paths.
- Không log location/PII — coords qua `GeoMath.redactedDescription`.
- Không `Task.detached` cho UI state mutation.
