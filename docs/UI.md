# Pickhour — iOS UI spec

Ghi chú tương tác/giao diện cho phần iOS. Nguyên tắc chung: **native-first** — SwiftUI + SF Symbols + system materials, không third-party UI library, không custom icon set. Mọi màn hình phải chạy tốt với Dynamic Type, VoiceOver, và Reduce Motion.

## Context menus (long-press)

Map-first app: long-press là interaction phụ chuẩn để giữ map sạch — action chính vẫn là tap thường.

### Spot pin (map annotation)

`.contextMenu` trên annotation, tối đa 5 items, icons = SF Symbols:

| Action | Title (EN) | systemImage | Ghi chú |
|---|---|---|---|
| Xem chi tiết | View Details | `eye` | Mở SpotDetail sheet (giống tap pin) |
| Tạo alert | Create Alert | `bell` | Mở AlertEditor prefill `spotId` |
| Yêu thích | Favorite | `heart` | Toggle; label/state đổi theo trạng thái |
| Chỉ đường | Directions | `arrow.triangle.turn.up.right.diamond` | `MKMapItem` → Apple Maps |
| Báo cáo | Report | `flag` | Mở report flow |

- Destructive actions (nếu có) dùng `Button(role: .destructive)`.
- Nếu `.contextMenu` trên SwiftUI `Map` annotation không ăn, fallback `UILongPressGestureRecognizer` trên `MKAnnotationView` — thử cách đầu trước.

### Alert rule row (Alerts list)

| Action | Title | systemImage |
|---|---|---|
| Sửa | Edit | `pencil` |
| Bật/Tắt | Disable / Enable | `bell.slash` / `bell` |
| Xóa | Delete | `trash` — `role: .destructive` |

### Forecast hour row (SpotDetail, optional)

Long-press một giờ trong forecast → "Remind me at this hour" (`alarm`) → AlertEditor prefill `startLocal`/`endLocal` = giờ đó.

## Push notification → deep link

- `NotificationDelegate` parse `kind == "alert.window"` + `spotId` → `DeepLinkRouter.pendingSpotID`.
- Map/RootView observe `pendingSpotID`, consume 1 lần → center map + mở SpotDetail.
- Payload contract: xem `docs/API.md` § Push payload.

## Quyền (permission timing)

- Location: chỉ "when in use", xin khi user bật location feature lần đầu — không xin lúc launch.
- Notifications: `PushManager.requestAuthorization()` chỉ gọi contextual (khi user tạo alert đầu tiên hoặc từ Settings), không xin lúc cold launch.
- StoreKit/paywall: chỉ khi user chủ động tap upgrade.

## Base components có sẵn (`MyApp/Components/`)

`ScoreBadge`, `ReasonChips`, `EmptyStateView` (wrap `ContentUnavailableView`), `LoadingSkeleton`/`.loading(_:)`. Dùng lại trước khi tạo component mới; component riêng chỉ khi thật sự cần và phải stateless.

## Design tokens

- Màu: xem `UI_SPEC.md` §2 (Meadow `AccentColor`; tier Great/Good = Meadow, Fair = orange, Poor = secondary).
- Font: system font + Dynamic Type; mono chỉ cho số liệu/ID.
- Tránh: custom fonts, emoji icons, glassmorphism quá mức, animation `transition-all`-style (dùng `.animation(_:value:)` có scope).
