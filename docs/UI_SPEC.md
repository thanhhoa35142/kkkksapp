# Pickhour — UI Spec v1

*2026-11-13 · iPhone, iPad, Mac, iPhone gập · SwiftUI + MapKit · chỉ dùng component chuẩn của Apple*

> Phiên bản tối thiểu: **đề xuất nâng từ iOS 17 lên iOS/iPadOS 18 và macOS 15** (lý do ở §10.1). Project hiện: iPhone + iPad iOS 17, **Mac native đã bật** (macOS 15, cùng target, không Catalyst; xem `SWIFT.md` § Nền tảng). Việc nâng iOS lên 18 vẫn cần bạn chốt.

File này là spec bố cục và màn hình. Các chi tiết tương tác đã chốt trong `UI.md` (context menu, deep link từ push, thời điểm xin quyền) vẫn giữ nguyên; spec này bổ sung chứ không thay thế. Code style theo `SWIFT.md`.

---

## 0. Nguyên tắc

1. **Trả lời một câu hỏi:** "Bây giờ / chiều nay / cuối tuần nên đi đâu?" Màn hình đầu tiên là câu trả lời đó, không phải bản đồ trống hay onboarding.
2. **Con số là nhân vật chính.** App không có ảnh (OSM không có ảnh), nên điểm số, lý do và hình dạng công viên trên bản đồ là phần nhìn chính.
3. **Native trước tiên.** `TabView`, `NavigationStack`, `List`/`Form` insetGrouped, `.sheet` có detents, `Menu`, `Gauge`, Swift Charts, `ContentUnavailableView`, `SubscriptionStoreView`, MapKit. Không dùng thư viện UI bên thứ ba, không tự vẽ tab bar, nav bar hay nút.
4. **Một màu thương hiệu duy nhất** (xanh lá, mục 2). Mọi màu khác lấy từ semantic colors của hệ thống.
5. **Không thứ gì chỉ dựa vào màu.** Điểm số luôn có số và nhãn chữ (Great/Good/Fair/Poor).

### Chống AI slop: danh sách cấm (review PR theo danh sách này)

| Cấm | Dùng thay |
|---|---|
| Gradient nền, gradient chữ, nút gradient | Nền `systemGroupedBackground`, nút `.borderedProminent` |
| Card lồng card, mọi thứ bọc trong khối bo 20–24pt có bóng | `List` insetGrouped (hệ thống tự bo góc), không đổ bóng tự chế |
| Glassmorphism tự chế, `.ultraThinMaterial` phủ khắp nơi | Material chỉ ở những chỗ hệ thống vốn dùng (sheet, overlay trên map) |
| Emoji làm icon, "✨", "🌳" trong copy | SF Symbols, rendering `.hierarchical` |
| Icon SF Symbol to đặt trong vòng tròn màu cho có | Icon chỉ đặt cạnh nội dung nó mô tả, cỡ theo font |
| **Spam icon:** icon trước mọi label, mọi tiêu đề section, mọi nút, mọi hàng Settings (kể cả ô vuông màu kiểu app Settings) | Theo "ngân sách icon" ở §2: icon chỉ khi nó mang nghĩa |
| **Sparkles và icon "AI/magic":** `sparkles`, `wand.and.stars`, `wand.and.rays`, `star.circle`, `bolt` để chỉ "thông minh" hay "nhanh", ✨ trong copy, chữ "AI-powered", "Smart picks" | Nói thẳng việc app làm: "Best Now", "Why 82?" |
| **Icon user/avatar:** `person.crop.circle` ở góc nav bar, ảnh đại diện giả, lời chào "Hi there 👋" | App không có tài khoản, nên không có avatar; Settings là một tab |
| Hero card "Top pick" kiểu landing page | Hàng đầu danh sách là kết quả số 1, cùng kiểu với các hàng khác |
| Onboarding carousel lướt trang (`TabView(.page)`), splash animation, xin quyền thông báo hoặc hiện paywall trong onboarding | Onboarding 3 bước kiểu Welcome của Apple (S0); quyền thông báo xin đúng lúc cần |
| Shimmer skeleton khắp nơi | `.redacted(reason: .placeholder)` trên đúng layout thật |
| Copy chung chung kiểu "Discover amazing spots!", "Your perfect day awaits" | Copy cụ thể: "82 · Clear, 21°, quiet" |
| Chữ IN HOA, letter-spacing rộng cho label | Text style hệ thống (`.headline`, `.footnote`…) |
| Tím/xanh dương "AI", nhiều màu nhấn | Chỉ một màu Meadow; cam/xám cho tier thấp |
| Animation spring nảy, `.transition` cho mọi view | `.animation(_:value:)` có phạm vi, tôn trọng Reduce Motion (danh sách đầy đủ ở §8) |
| `.foregroundStyle(.green.gradient)`, `Color.gradient`, `LinearGradient` ở bất cứ đâu (kể cả Charts, Gauge) | Màu phẳng theo token §2 |
| Đổ bóng (`.shadow`) để tạo độ nổi | Phân lớp bằng màu nền hệ thống (§2, bảng nền) |
| Số liệu giả, "4.8 ★ (2.3k)" | Chỉ hiện dữ liệu thật mà API trả về |
| Paywall blur nội dung, chặn vòng lặp chính | Hàng "See 17 more with Plus" ở cuối danh sách, `SubscriptionStoreView` |

---

## 1. Danh sách màn hình

Gồm **1 luồng onboarding (3 bước), 4 tab gốc, 1 màn push và 7 sheet, tổng 13 view**. Widget để giai đoạn sau (mục 6).

| # | Màn hình | Loại | Yêu cầu | Ưu tiên |
|---|---|---|---|---|
| S0 | **Onboarding** (Welcome → Where → Who) | `fullScreenCover`, chỉ lần đầu | F3, cá nhân hóa §8 | P0 |
| S1 | **Best Now** (gợi ý quanh tôi) | Tab 1 | D2, D3, F3 | P0 |
| S2 | **Map** | Tab 2 | F1, F3, D4 | P0 |
| S3 | **Saved** (yêu thích + cảnh báo) | Tab 3 | F5, D6 | P0 / P1 |
| S4 | **Settings** | Tab 4 | i18n, riêng tư, gói | P0 |
| S5 | **Spot Detail** | Push (từ list), sheet (từ map) | F2, F4, D1, D3 | P0 |
| S6 | When picker | Sheet | D1, D2 | P0 |
| S7 | Score breakdown "Why 82?" | Sheet | D3, phản hồi điểm | P0 |
| S8 | Filters | Sheet | F6 | P1 |
| S9 | Report / Crowd report | Sheet | D5, §16 | P1 |
| S10 | Alert editor | Sheet | D6 | P1 |
| S11 | Paywall | Sheet | §15 | P1 |
| S12 | Location search | `.searchable` (S1, S2) | F3 | P0 |

Trên iPad, Mac và iPhone gập khi mở, Best Now và Map gộp thành một tab **Explore** (danh sách và bản đồ cạnh nhau, xem §10). Số view không đổi, chỉ cách xếp khác.

Tìm kiếm (S12) không phải màn riêng: đó là `.searchable` kết hợp `MKLocalSearchCompleter`, dùng chung cho S1 và S2.

### Sơ đồ điều hướng

```
Onboarding (fullScreenCover, lần đầu) ──▶ Welcome ─push─▶ Where ─push─▶ Who ──dismiss──▶
TabView
├─ Best Now ── NavigationStack ── [row] ──push──▶ Spot Detail ──sheet──▶ Why 82? / Report / Alert editor
│     toolbar: [Location ▾]  [When ▾]  [Filter]
├─ Map ─────── NavigationStack ── [pin] ──sheet (detents)──▶ Spot Detail (giống trên)
│     toolbar: [When ▾]  [Filter]   .searchable
├─ Saved ───── NavigationStack ── [row] ──push──▶ Spot Detail
│                                └─ [alert] ──sheet──▶ Alert editor
└─ Settings ── NavigationStack ── Form ──▶ Plan (Paywall sheet), Units, About & data sources
```

**Trạng thái "When" dùng chung** (`AppState.when`, `@Observable`): đổi ở Best Now thì Map và Saved cũng đổi theo. Thanh toolbar luôn cho biết đang xem giờ nào, ví dụ "Today 3 PM".

---

## 2. Màu, chữ, khoảng cách

### Màu (phẳng kiểu SaaS: nền trung tính, một màu thương hiệu, không gradient, không bóng)

Toàn bộ giao diện là các lớp nền xám trung tính của hệ thống. Màu chỉ xuất hiện ở ba chỗ: **Meadow** (thương hiệu và hành động), **màu trạng thái** (cam, đỏ) và **bản đồ**. Nền, chữ và đường kẻ đều dùng semantic color của iOS, nên tự đúng ở dark mode, Increase Contrast và Smart Invert.

**Nền và chữ (dùng thẳng system color, không tự định nghĩa)**

| Token | System color | Light | Dark | Dùng cho |
|---|---|---|---|---|
| `bg` | `systemGroupedBackground` | `#F2F2F7` | `#000000` | Nền màn hình |
| `surface` | `secondarySystemGroupedBackground` | `#FFFFFF` | `#1C1C1E` | Hàng của List/Form, sheet |
| `surface2` | `tertiarySystemGroupedBackground` | `#F2F2F7` | `#2C2C2E` | Ô lồng trong hàng (hiếm) |
| `fill` | `.fill.tertiary` | xám 12% | xám 24% | Nền nút `.bordered`, track của Gauge |
| `text` | `.primary` / `label` | `#000000` | `#FFFFFF` | Tên, số |
| `text2` | `.secondary` | `#3C3C43` 60% | `#EBEBF5` 60% | Dòng phụ, lý do |
| `text3` | `.tertiary` | `#3C3C43` 30% | `#EBEBF5` 30% | Placeholder, đơn vị |
| `line` | `separator` | hệ thống | hệ thống | Đường kẻ (List tự vẽ) |

**Thương hiệu Meadow (Asset Catalog, có biến thể Any/Dark và High Contrast)**

| Token | Light | Dark | High Contrast (light / dark) | Dùng cho |
|---|---|---|---|---|
| `AccentColor` = **Meadow** | `#2E7D4F` | `#5DC983` | `#1F5E39` / `#7FDB9D` | Tint toàn app, nút chính, tier Great/Good, viền polygon |
| `MeadowSoft` | `#E8F3EC` | `#16301F` | | Nền nhạt phía sau số điểm, hàng đang chọn, phần tô polygon (dạng opacity trên map) |
| `OnMeadow` | `#FFFFFF` | `#08210F` | | Chữ trên nền Meadow (nút `.borderedProminent` đã tự xử lý) |

**Trạng thái**

| Token | Màu | Dùng cho |
|---|---|---|
| tier Great / Good | Meadow | Điểm 60–100 (khác nhau bằng số, nhãn và độ đầy Gauge) |
| tier Fair | `.orange` | Điểm 40–59 |
| tier Poor | `.secondary` | Điểm < 40 |
| warning | `.orange` | Bị chặn trần vì mưa hoặc nóng (kèm symbol) |
| danger | `.red` | Chỉ cho xóa và "closed"; **không** dùng cho điểm thấp |
| info | `.secondary` | Offline, dữ liệu cũ (không dùng xanh dương) |

Quy tắc:
- Không có `LinearGradient`/`RadialGradient`/`.gradient` ở bất cứ đâu, kể cả `BarMark`, `Gauge`, nút hay nền.
- Không `.shadow`. Độ nổi là chuyện của hệ thống: sheet, menu và overlay trên map đã có material và bóng riêng.
- Tỷ lệ màu trên một màn ước chừng 90% trung tính, 8% Meadow, 2% trạng thái. Không màn nào có quá 2 phần tử nền Meadow đặc (thường chỉ nút chính).
- Độ tương phản: Meadow light trên trắng khoảng 5.0:1, dark trên đen khoảng 10:1, đều đạt AA. Meadow trên `MeadowSoft` chỉ khoảng 4.4:1 ở light, nên cặp này **chỉ dùng cho chữ lớn hoặc đậm** (số điểm, ≥ 17pt semibold), không dùng cho chữ thường. Kiểm lại bằng Accessibility Inspector trên máy thật.
- Vì sao Great và Good cùng màu: hai sắc xanh lá gần nhau rất khó phân biệt, nhất là với người mù màu.
- `ScoreBadge.swift` hiện dùng `.green/.mint/.orange/.red` → đổi thành Meadow/Meadow/orange/secondary, nền `MeadowSoft`.
- Bị chặn trần vì mưa hoặc nóng (`capReason`): thêm symbol `cloud.rain.fill` hoặc `thermometer.sun.fill` cạnh số.

### Chữ (chỉ font hệ thống, Dynamic Type)

| Vai trò | Text style | Ghi chú |
|---|---|---|
| Tiêu đề tab | `.largeTitle` (nav bar large title) | Hệ thống tự xử lý |
| Tên điểm ở Detail | `.title2.bold()` | Tối đa 2 dòng |
| Số điểm lớn ở Detail | `.system(.largeTitle, design: .rounded).bold().monospacedDigit()` | Chỗ duy nhất dùng `.rounded` |
| Tên điểm trong hàng | `.headline` | |
| Dòng phụ (loại · khoảng cách) | `.subheadline`, `.secondary` | |
| Lý do, nguồn dữ liệu | `.footnote`, `.secondary` | |
| Số liệu (°, km, giờ) | `.monospacedDigit()` | Để số không nhảy khi đổi |

### Khoảng cách

Dùng margin mặc định của `List`/`Form` và padding mặc định của hệ thống. Chỉ khi tự layout (header của Detail, overlay trên map) mới dùng lưới 4pt: 8 / 12 / 16 / 20. Không đặt `cornerRadius` tự chế trừ overlay trên map (dùng `.buttonBorderShape(.capsule)` hoặc `.roundedRectangle`).

### Icon theo loại điểm (SF Symbols; kiểm tên trong app SF Symbols trước khi code)

| kind | Symbol | Nhãn |
|---|---|---|
| park | `tree.fill` | Park |
| beach | `beach.umbrella.fill` | Beach |
| site | `basket.fill` | Picnic area |
| table | `table.furniture.fill` | Picnic table |

Tiện ích: toilet `toilet.fill`, water `drop.fill`, bbq `flame.fill`, playground `figure.play`, shelter `tent.fill`, parking `parkingsign`, bicycle_parking `bicycle`, dog_area `dog.fill`.

### Ngân sách icon (chống spam icon)

Một icon chỉ được xuất hiện khi rơi vào một trong ba trường hợp:
1. **Control chuẩn của hệ thống:** icon của tab bar, nút trên toolbar (Filter, Share, Save), chevron của `NavigationLink`, nút của map.
2. **Mã hóa một loại:** loại điểm (park, beach…), loại tiện ích, loại lý do (thời tiết, độ đông). Icon giúp quét nhanh một danh sách cùng loại.
3. **Thay cho một chữ:** `lock.fill` (cần Plus), `wifi.slash` (offline), `cloud.rain.fill` cạnh số điểm bị chặn trần.

Còn lại thì **không dùng icon**:
- Tiêu đề màn, tiêu đề section, footer: chỉ có chữ.
- Hàng trong Settings và Form: chỉ có chữ, không có ô vuông màu.
- Nút có chữ (Continue, Directions, Save trong Form…): chỉ chữ. Ngoại lệ là nhóm nút hành động ở S5, chỗ mỗi nút là một icon kèm nhãn ngắn, giống Apple Maps.
- Hàng `SpotRow` trong danh sách: **không** có icon trước lý do; `ScoreBadge` đã là điểm nhấn thị giác duy nhất của hàng.

Giới hạn đếm được: **tối đa 1 icon trên mỗi hàng** (không tính chevron và control hệ thống), và **tối đa khoảng 8 icon không phải control** trên một màn nhìn thấy cùng lúc. Review PR thì đếm.

### Điểm không có tên (1.387 trên 15.091 điểm đang hiện, phần lớn là `site`)

`NameResolver`: `names[lang]` → `names["en"]` → `name` → **nhãn loại kèm thành phố** ("Picnic area · Utrecht"). Không bao giờ hiện "—" hay ID.

---

## 3. Bố cục từng màn

Kích thước tham chiếu là iPhone 15 (393×852pt). Wireframe chỉ thể hiện cấu trúc; khoảng cách thật do hệ thống quyết định.

### S0 · Onboarding (chỉ lần đầu mở app)

Theo mẫu màn Welcome trong app của chính Apple (Notes, Freeform, Journal), **không** phải carousel lướt trang. Hiện bằng `fullScreenCover` khi `@AppStorage("onboardingDone") == false`. Bên trong là một `NavigationStack` 3 bước, chuyển bằng push chuẩn, có nút Back. Từ lúc mở app đến lúc thấy nội dung tối đa 3 lần chạm.

```
 Bước 1 · Welcome              Bước 2 · Where                Bước 3 · Who (tùy chọn)
┌───────────────────────┐    ┌───────────────────────┐    ┌───────────────────────┐
│                       │    │ ‹ Back                │    │ ‹ Back           Skip │
│      [App icon]       │    │ Where do you          │    │ Who's coming          │
│                       │    │ picnic?               │    │ along?                │
│  Welcome to           │    │                       │    │ We'll favor spots     │
│  Pickhour             │    │ We use your location  │    │ that suit them.       │
│                       │    │ only while the app is │    │                       │
│ [gauge] Best spot     │    │ open and never store  │    │ ┌───────────────────┐ │
│   right now           │    │ it.                   │    │ │ Kids            ✓ │ │
│   Hourly score 0–100  │    │                       │    │ │ Dog               │ │
│ [text.bubble] Why     │    │                       │    │ │ Friends           │ │
│   it's good           │    │                       │    │ │ Just us two       │ │
│   Weather, crowd,     │    │                       │    │ └───────────────────┘ │
│   toilets nearby      │    │                       │    │                       │
│ [calendar] Plan the   │    │                       │    │                       │
│   weekend             │    │ [ Use My Location   ] │    │ [  Start Exploring  ] │
│                       │    │ [ Choose a City     ] │    │                       │
│ [     Continue      ] │    │                       │    │                       │
│ Map data © OSM        │    │                       │    │                       │
└───────────────────────┘    └───────────────────────┘    └───────────────────────┘
```

- **Bước 1 · Welcome:** ảnh App Icon thật cỡ 64pt (bo góc theo `RoundedRectangle(cornerRadius: 14, style: .continuous)`), không dùng SF Symbol phóng to làm logo. Tiêu đề `.largeTitle.bold()`. Ba hàng `Label`: icon Meadow `.hierarchical` cỡ `.title2`, tiêu đề `.headline` và mô tả `.subheadline` màu secondary. Nút "Continue" `.borderedProminent` `.controlSize(.large)` rộng hết khung, nằm trong `safeAreaInset(edge: .bottom)`. Đây là màn duy nhất có ghi nguồn OSM ngay từ đầu.
- **Bước 2 · Where:** "Use My Location" gọi xin quyền *when in use* ngay khi bấm (đúng ngữ cảnh, theo `UI.md`); được cấp hay bị từ chối đều đi tiếp. "Choose a City" push sang danh sách city pack theo nước (`.searchable`) và ghi nhớ vị trí mặc định. Không có nút Skip vì app cần một vị trí để trả lời.
- **Bước 3 · Who:** `List` chọn nhiều, mỗi hàng có checkmark; có thể không chọn gì. Lựa chọn được lưu thành filter mặc định và cá nhân hóa nhẹ: Kids tăng trọng số toilet và playground (yêu cầu §8), Dog bật filter dog area. Có Skip; "Start Exploring" đóng cover và vào thẳng Best Now.
- **Không có trong onboarding:** xin quyền thông báo, paywall, tạo tài khoản, slide giới thiệu tính năng.
- Ghi sự kiện `onboarding_completed` (kèm bước đã bỏ qua) qua `EventQueue`. Settings có mục "Show Welcome Again" để xem lại.
- Dynamic Type lớn: màn Welcome nằm trong `ScrollView`, nút vẫn dính đáy nhờ `safeAreaInset`.

### S1 · Best Now (tab 1, màn mở app)

```
┌─────────────────────────────────────┐
│ ◉ Amsterdam ▾            Today 3 PM ▾ ⚲│  toolbar: Menu vị trí · Menu When · Filter
│ Best Now                            │  large title
│ ┌─ Search places ─────────────────┐ │  .searchable
├─────────────────────────────────────┤
│  TOP PICKS · 3 PM          (header) │  section header hệ thống (chữ thường)
│ ┌─────────────────────────────────┐ │
│ │ (82)  Vondelpark                │ │  ScoreBadge 44pt | headline
│ │       Park · 1.2 km             │ │  subheadline secondary
│ │       Clear, 21° · Usually quiet│ │  footnote: lý do #1–2
│ ├─────────────────────────────────┤ │
│ │ (78)  Westerpark            …   │ │
│ ├─────────────────────────────────┤ │
│ │ (71)  Picnic area · Sloterpark  │ │
│ └─────────────────────────────────┘ │
│  ┌ See 17 more with Plus ────────┐  │  Free: hàng cuối, mở S11
│                                     │
│  Map data © OpenStreetMap           │  section footer
├─────────────────────────────────────┤
│  Best Now   Map   Saved   Settings  │  TabView
└─────────────────────────────────────┘
```

- `List(.insetGrouped)`, mỗi hàng là `NavigationLink` push sang S5. Kéo xuống để làm mới (`.refreshable`).
- Hàng điểm (`SpotRow`, tái dùng ở S3): `ScoreBadge` bên trái, ba dòng chữ. Vuốt sang trái: Save; context menu theo `UI.md`.
- Ở Dynamic Type ≥ `.accessibility1`: `ScoreBadge` lên trên, chữ xuống dưới (`ViewThatFits` hoặc kiểm `dynamicTypeSize`).
- **Bỏ qua onboarding hoặc từ chối quyền vị trí:** thay danh sách bằng một section có 2 nút, "Use My Location" (`.borderedProminent`) và "Choose a City" (mở S12). Chỉ xin quyền khi bấm nút.
- **Ngoài vùng phủ** (không có city pack gần): `ContentUnavailableView("No spots here yet", systemImage: "map", description: "Pickhour covers 39 cities in 18 countries.")` kèm nút "Browse Cities".
- Free hiện 3 kết quả, Plus không giới hạn (§15). Server đã giới hạn sẵn; app chỉ hiện hàng upsell.

### S2 · Map (tab 2)

```
┌─────────────────────────────────────┐
│ Map                 Today 3 PM ▾  ⚲ │  inline title · When · Filter
│ ┌─ Search places ─────────────────┐ │
├─────────────────────────────────────┤
│          ┌ Search This Area ┐       │  capsule .bordered, hiện khi map đã dịch chuyển
│     (82)         ▓▓▓▓               │  Marker monogram = điểm số, tint theo tier
│           (12)  ▓▓polygon▓▓  (64)   │  cluster: số lượng điểm, tint Meadow
│                  ▓▓▓▓               │
│                               ◎ ⌖   │  MapUserLocationButton, MapCompass
│ ─────────── sheet .height(200) ───  │  khi đã chọn pin
│  Vondelpark                  (82)   │
│  Park · 1.2 km · Clear, 21°         │
│  [ Directions ] [ ♡ ] [bell] [ ⋯ ]  │
├─────────────────────────────────────┤
│  Best Now   Map   Saved   Settings  │
└─────────────────────────────────────┘
```

- **Gom cụm (F1) cần `MKMapView`** qua `UIViewRepresentable`: SwiftUI `Map` trên iOS 17 chưa hỗ trợ clustering. Dùng `MKMarkerAnnotationView` với `clusteringIdentifier`, `glyphText` là điểm số, `markerTintColor` theo tier. Vẫn là component chuẩn của Apple.
- Zoom gần (ví dụ span < 0.05°): vẽ `MKPolygon` của công viên (`area` từ S5 hoặc từ GeoJSON của bbox) với viền Meadow 1.5pt và phần tô `MeadowFill`. Đây là thứ thay cho ảnh.
- Chạm pin mở sheet S5 với `.presentationDetents([.height(200), .large])` và `.presentationBackgroundInteraction(.enabled(upThrough: .height(200)))`, giống Apple Maps. Kéo lên `.large` để xem đầy đủ.
- Chỉ gọi `GET /v1/spots?bbox=` khi map dừng di chuyển (debounce 300ms qua `.task(id:)`). Nút "Search This Area" chỉ hiện khi khung nhìn đã đi quá 30% so với lần tải trước.
- Attribution OSM: `MKMapView` tự hiện "Legal" của Apple; thêm nhãn "© OpenStreetMap" (`.caption2`) ở góc dưới trái, phía trên chỗ Legal.

### S5 · Spot Detail

```
┌─────────────────────────────────────┐
│ ‹ Best Now                    ⤴  ♡  │  nav bar inline: Share, Save
│ ┌─────────────────────────────────┐ │
│ │   bản đồ tĩnh 160pt             │ │  Map non-interactive + polygon Meadow
│ │   ▓▓▓ polygon ▓▓▓               │ │  (thay cho ảnh)
│ └─────────────────────────────────┘ │
│  Vondelpark                         │  title2 bold
│  Park · 1.2 km · Amsterdam          │  subheadline secondary
│                                     │
│  82  Great                    (◔)   │  số lớn rounded + nhãn + Gauge
│  Today 3 PM · Medium confidence  ⓘ  │  footnote; ⓘ → S7
│  [sun] Clear, 21°                       │  tối đa 3 lý do (ReasonLocalizer)
│  [people] Usually quiet at this hour      │  [x] = SF Symbol
│  [toilet] Toilets and water nearby        │
│                                     │
│ [  Directions  ] [Alert] [Report]   │  1 .borderedProminent + 2 .bordered
├─ Next 24 hours ─────────────────────┤
│  ▁▃▅▇█▇▅▃▂▁▁▁ … (Swift Charts)      │  BarMark theo giờ, giờ đang chọn = Meadow
│  Mon Tue Wed Thu Fri Sat Sun [lock]      │  Picker .segmented; Free: ngày 3+ có khóa
├─ Amenities ─────────────────────────┤
│  [toilet] Toilets                   40 m  │  List rows, distance monospacedDigit
│  [drop] Drinking water           120 m  │
│  [flame] BBQ                      300 m  │
├─ About ─────────────────────────────┤
│  Last verified       12 Oct 2026    │
│  Source              OpenStreetMap  │
│  Is this spot still here?        ›  │  → S9
│                                     │
│  Map data © OpenStreetMap contrib.  │  footer: OSM + nguồn thời tiết
│  Weather:  Apple Weather / Open-Meteo│
└─────────────────────────────────────┘
```

- Là `List(.insetGrouped)`; phần header (bản đồ, tên, điểm, nút) là section đầu với `listRowInsets` tự chỉnh.
- **Biểu đồ giờ (D1):** `Chart { BarMark(x: .value("Hour", h), y: .value("Score", s)) }`, chiều cao 120pt. Màu cột theo tier, cột đang chọn là Meadow đậm. Chạm hoặc kéo dùng `chartXSelection` để đổi giờ đang xem; long-press một giờ thì mở "Remind me at this hour" (`UI.md`).
- **Chọn ngày:** Free được 24 giờ tới (§15). Các ngày ngoài 24h hiện `lock.fill`, bấm vào mở S11, không làm mờ biểu đồ.
- **Nút hành động:** Directions dùng `MKMapItem.openInMaps`. Alert mở S10 (lần đầu sẽ xin quyền thông báo). Report mở S9. Save nằm trên nav bar (`heart` / `heart.fill`).
- **Độ đông:** khi chỉ có ước lượng từ mô hình, luôn ghi "Estimate" (§16) và mức tin cậy không vượt Medium (server đã giới hạn).
- **Không có tiện ích:** ẩn hẳn section Amenities, không hiện "No amenities".

### S3 · Saved (tab 3)

```
│ Saved                         Edit  │
├─ Places ────────────────────────────┤
│ (82) Vondelpark      Park · 1.2 km  │  SpotRow, điểm theo When hiện tại
│ (64) Bondi Beach    Beach · 16k km  │
├─ Alerts ────────────────────────────┤
│ [bell] Vondelpark                  [on] │  Toggle
│    Sat–Sun · 10 AM–6 PM · 75+       │  footnote
│ ＋ New Alert                         │  → S10
```

- Favorites lưu trên máy bằng SwiftData; Free tối đa 10 (§15). Alerts lấy từ `GET /v1/alerts`, Free 1 khu vực.
- Trống: `ContentUnavailableView("No saved places", systemImage: "heart", description: "Tap Save on a spot to keep it here.")`.

### S4 · Settings (tab 4)

`Form` gồm các section:

1. **Plan:** "Pickhour Plus · renews 12 Nov 2027" hoặc nút "Upgrade to Plus" (mở S11); "Restore Purchases".
2. **Units:** Temperature (Automatic/°C/°F), Distance (Automatic/km/mi), dùng `Picker` kiểu `.menu`.
3. **Permissions:** Location, Notifications, hiện trạng thái kèm nút "Open Settings" (`UIApplication.openSettingsURLString`).
4. **Language:** một dòng mở cài đặt ngôn ngữ riêng của app trong iOS (per-app language), không tự làm bộ chọn ngôn ngữ.
5. **Privacy:** Privacy Policy (link); "Delete My Data" (`role: .destructive`, có `confirmationDialog`) gọi `DELETE /v1/devices/{id}`.
6. **About:** Data Sources & Attribution (push: OSM/ODbL, nguồn thời tiết, crowd = estimate), Version.

### S6 · When picker (sheet, `.medium`)

- Hai chỗ mở: `Menu` trên toolbar với lựa chọn nhanh "Now · In 2 hours · This Evening · Tomorrow Morning · Saturday · Sunday", và mục "Choose a Time…" mở sheet.
- Sheet: `DatePicker` kiểu `.graphical` cho ngày (giới hạn 7 ngày) cộng `Picker` giờ (bước 1 giờ, vì điểm tính theo giờ). Ngày ngoài 24h với Free hiện khóa.
- Nhãn trên toolbar theo múi giờ của điểm hoặc thành phố đang xem ("Sat 10 AM").

### S7 · Score breakdown "Why 82?" (sheet, `.medium` / `.large`)

```
│ Why 82?                        Done │
│ Weather     ████████░░  40%    85  │  Gauge(.linearCapacity) cho từng thành phần
│ Crowd       ██████░░░░  25%    70  │  tên · thanh · trọng số · điểm
│ Amenities   █████████░  20%    90  │
│ Shade       ░░░░░░░░░░  10%     —  │  "—" = thiếu dữ liệu, trọng số đã chuẩn hóa lại
│ Freshness   ███████░░░   5%    75  │
│ Capped at 40 because of rain risk   │  chỉ khi có capReason
│ Medium confidence: crowd is an      │
│ estimate, not live data.            │
│ Is this score right?   [thumbsdown] [–] [thumbsup]     │  POST /v1/scores/feedback (SF Symbols hand.thumbsdown…)
```

### S8 · Filters (sheet, `.medium`) — P1

`Form`: Kind (toggle đa chọn: Park, Beach, Picnic area, Picnic table), Must have (Toilets, Water, BBQ, Playground, Shelter, Dog area), Minimum score (`Picker` 40/60/80). Nút "Reset" bên trái, "Done" bên phải. Khi đang có filter, icon toolbar chuyển sang dạng `.fill`.

### S9 · Report (sheet, `.medium`) — P1

`Form` có hai section:
1. **How busy is it right now?** dùng `Picker(.segmented)` Quiet / Moderate / Busy, gọi `POST /crowd-reports`. Chỉ bật khi người dùng ở gần (kiểm khoảng cách trên máy); nếu ở xa thì section này ẩn kèm footer giải thích.
2. **Is this spot correct?** gồm "Still here" (một chạm, gọi `confirm`), "It's gone", "It's closed", "Something's wrong…" (Picker các `issueCode`).

Gửi xong: đóng sheet và hiện xác nhận ngắn qua `.sensoryFeedback(.success)`. Không dùng toast hay alert.

### S10 · Alert editor (sheet, `.large`) — P1

`Form`: Spot (tên điểm, hoặc "Area around Amsterdam" với radius `Picker` 1/3/5 km), Notify when score is at least (`Stepper` bước 5, mặc định 75), Days (7 toggle trong `DisclosureGroup`, hoặc preset Weekends/Every day), Between (hai `DatePicker(.hourAndMinute)`), Enabled. Toolbar có Cancel / Save. Free đã có 1 khu vực mà tạo thêm thì mở S11 thay vì lưu.

### S11 · Paywall (sheet)

`SubscriptionStoreView(groupID:)` của StoreKit 2 với `.subscriptionStoreControlStyle(.prominentPicker)`. Phần marketing là 3 dòng `Label` (7-day forecast, unlimited picks, more alerts), ảnh App Icon ở trên cùng, không có ảnh minh họa, không `sparkles` hay icon "premium" (`crown`, `star`). Mở **chỉ** từ các điểm chạm §15 (ngày 3+, alert thứ hai, hàng "See more"), không bao giờ tự bật lên.

---

## 4. Trạng thái chung

| Trạng thái | Cách hiện |
|---|---|
| Đang tải lần đầu | Layout thật + `.redacted(reason: .placeholder)` (`LoadingSkeleton` hiện có) |
| Làm mới | `.refreshable` (List), `ProgressView` nhỏ trên toolbar (Map) |
| Lỗi mạng, có cache | Giữ dữ liệu cũ + section header "Offline · Updated 2 hours ago" (`.footnote`, symbol `wifi.slash`) |
| Lỗi mạng, không cache | `ContentUnavailableView` + nút "Try Again" |
| Dữ liệu điểm cũ (`computedAt` > 3 giờ) | Dòng footnote "Updated 3 h ago" dưới điểm số; không chặn |
| Không có điểm số | `ScoreBadge` hiện "–" màu secondary, nhãn "No forecast yet" |

## 5. Trợ năng và địa phương hóa

- **VoiceOver:** mỗi `SpotRow` là một element (`.accessibilityElement(children: .combine)`), đọc thành câu như "Vondelpark, park, 1.2 kilometers, score 82, great, clear and 21 degrees". Biểu đồ giờ có `AXChartDescriptor`.
- **Dynamic Type** tới AX5: hàng chuyển sang dạng xếp dọc; bản đồ tĩnh ở S5 ẩn đi ở cỡ AX3 trở lên.
- **Reduce Motion:** tắt animation khi đổi giờ trên biểu đồ.
- **Chuỗi:** String Catalog (`.xcstrings`), số nhiều qua catalog, đơn vị qua `Measurement` + `FormatStyle`, giờ theo `tz` của điểm.
- **Mã lý do:** `ReasonLocalizer` ánh xạ `weather.clear`, `weather.rain_risk`, `weather.hot`, `weather.cold`, `crowd.low|moderate|high`, `amenity.well_equipped`, `fresh.recent` sang câu ngắn kèm SF Symbol. Mã chưa biết thì bỏ qua, không hiện mã thô.
- **Thuật ngữ:** "Picnic area" / "Picknickplatz" / "Aire de pique-nique"… lấy từ bảng thuật ngữ trong yêu cầu §11.

## 6. Widget (giai đoạn sau, D7)

`systemSmall`: một điểm tốt nhất ("82 · Vondelpark · 3 PM"). `systemMedium`: top 3 cộng giờ. Dùng `containerBackground(.fill.tertiary)`, tint Meadow, không có ảnh. `accessoryCircular` cho Lock Screen: `Gauge` hiện điểm.

## 7. Backend cần thêm để UI chạy đủ

| Thiếu | Ảnh hưởng | Đề xuất |
|---|---|---|
| Nguồn thời tiết không có trong response | S5 không biết ghi "Apple Weather" hay "Open-Meteo" (cả hai đều bắt buộc ghi nguồn) | Thêm `weatherSource` vào forecast/detail |
| Lấy điểm số cho nhiều id | S3 Saved phải gọi N request | `GET /v1/spots?ids=…&when=` |
| `t_holidays` trống | Độ đông ngày lễ sai, không đổi được gì ở UI | Job `holidays.refresh` |
| Polygon trong bbox | S2 phải gọi detail từng điểm để vẽ polygon | Trả `area` đã đơn giản hóa (`ST_SimplifyPreserveTopology`) khi zoom gần |
| Danh sách city pack | Nút "Browse Cities" ở S1 | `GET /v1/packs` (slug, name, country, center) |
| Điểm nhiều giờ trong bbox | Time-lapse M1 phải gọi 12 lần | `GET /v1/spots?bbox=&from=&hours=12` trả mảng điểm theo giờ cho mỗi spot |

---

## 8. Animation và transition

Nguyên tắc: **chuyển động chỉ để giải thích thay đổi, không để trang trí.** Ưu tiên tuyệt đối transition của hệ thống. Toàn app chỉ có một animation "đặc trưng": con số điểm đổi bằng `numericText` khi đổi giờ.

| Chỗ | Cách làm | Thời lượng | Khi bật Reduce Motion | Đánh giá |
|---|---|---|---|---|
| Push/pop (List → Detail, Onboarding) | `NavigationStack` mặc định | hệ thống | hệ thống tự xử lý | Giữ |
| Sheet, kéo giữa các detent | `.sheet` + `presentationDetents` | hệ thống | hệ thống | Giữ |
| Mở/đóng onboarding | `fullScreenCover` mặc định | hệ thống | hệ thống | Giữ |
| Đổi tab | Không animation (mặc định của iOS) | 0 | – | Giữ; cấm tự thêm hiệu ứng đổi tab |
| **Số điểm đổi khi đổi "When"** | `.contentTransition(.numericText(value:))` + `.animation(.snappy(duration: 0.25), value: score)` | 0.25 s | chỉ crossfade (`.opacity`) | Giữ, đây là animation đặc trưng |
| Vòng Gauge đầy hoặc vơi | `.animation(.easeInOut(duration: 0.25), value: score)` | 0.25 s | đổi ngay | Giữ |
| Danh sách sắp xếp lại khi đổi giờ | **Không** animate việc đổi thứ tự (nhảy hàng hàng loạt rất rối) | 0 | – | Chỉ số trong badge animate |
| Kéo trên biểu đồ giờ | Highlight cột đổi ngay + `.sensoryFeedback(.selection, trigger: hour)` | 0 | như cũ | Giữ; haptic thay cho animation |
| Bấm Save | `.symbolEffect(.bounce, value: isSaved)` + `.sensoryFeedback(.impact(weight: .light), trigger: isSaved)` | hệ thống | hệ thống tự giảm | Giữ |
| Camera bản đồ (chọn pin, deep link) | `setRegion(animated: true)` của MapKit | hệ thống | `animated: false` | Giữ |
| Nút "Search This Area" | `.transition(.move(edge: .top).combined(with: .opacity))` | 0.2 s | chỉ opacity | Giữ |
| Đang tải → có nội dung | Bỏ `.redacted`, `.animation(.default, value: isLoading)` | ~0.25 s | đổi ngay | Giữ |
| Kéo để làm mới | `.refreshable` | hệ thống | hệ thống | Giữ |
| Gửi report xong | Đóng sheet + `.sensoryFeedback(.success)` | hệ thống | như cũ | Giữ; không toast, không confetti |
| Paywall | `SubscriptionStoreView` mặc định | hệ thống | hệ thống | Giữ |

**Cấm:** spring nảy trên card hay hàng, parallax, `matchedGeometryEffect` kiểu hero (không có ảnh thì vô nghĩa), pin nhấp nháy hay pulse, shimmer, Lottie, confetti, animation tự chạy lặp (trừ Time-lapse §8.1 khi người dùng bấm Play), animation UI trên 0.35 s (motion graphic §8.1 có giới hạn riêng), `.animation(_:)` không có `value:` (deprecated, animate lan cả view), custom `.navigationTransition`.

**Đánh giá chung: 9/10.** Gần như mọi chuyển động là của hệ thống, nên tự đúng chuẩn, đúng Reduce Motion và nhanh. Bị trừ 1 điểm vì còn một rủi ro chưa kiểm: khi đổi "When", ba chỗ cùng đổi một lúc (số, Gauge, thứ tự danh sách). Phải thử trên máy xem có rối không; nếu rối thì tắt animation Gauge, chỉ giữ số.


### 8.1 Motion graphic

Có làm, nhưng theo một luật: **motion graphic phải vẽ ra dữ liệu thật, không để trang trí.** Ý tưởng cốt lõi của app là "điểm số thay đổi theo giờ", nên chuyển động hợp lý nhất là cho người dùng *thấy* thời gian trôi. Chỉ dùng API của Apple (`PhaseAnimator`, `KeyframeAnimator`, `TimelineView`, Swift Charts, SF Symbol effects), không Lottie, không video.

| # | Motion | Ở đâu | Cách làm | Thời lượng | Reduce Motion | Ưu tiên |
|---|---|---|---|---|---|---|
| M1 | **Time-lapse điểm số trên bản đồ** | Map, nút Play ▸ trên toolbar | Chạy qua 12 giờ tới, mỗi giờ khoảng 0.6 s: glyph trên pin đổi số bằng `numericText`, màu tier đổi theo; thanh giờ ở đáy chạy theo. Bấm Pause hoặc chạm map là dừng ở giờ đó, và giờ đó trở thành "When" | khoảng 7 s cho 12 giờ, do người dùng bật | Không chạy tự động; thay bằng `Slider` giờ để kéo tay | P1, điểm khác biệt chính |
| M2 | **Biểu đồ "ngày của bạn"** | Onboarding bước 1, phía trên 3 dòng giới thiệu | 24 cột `BarMark` mọc lên lần lượt bằng `KeyframeAnimator`, rồi cột giờ tốt nhất đổi sang Meadow kèm nhãn "Best at 3 PM". Dữ liệu là forecast thật của một công viên gần (hoặc của thành phố mặc định) | 1.2 s, chạy **một lần** | Hiện ngay khung hình cuối | P0 |
| M3 | **Gauge vẽ vào** | Spot Detail, lần đầu mở một điểm | Vòng điểm chạy từ 0 đến giá trị thật, số đếm lên bằng `numericText` | 0.5 s, một lần cho mỗi điểm | Hiện ngay giá trị | P1 |
| M4 | **Đường mặt trời** | Spot Detail, dưới biểu đồ giờ | Đường cong `LineMark` từ bình minh tới hoàng hôn (tính trên máy từ tọa độ và ngày), chấm mặt trời trượt theo giờ đang chọn | theo thao tác kéo, không tự chạy | Chấm nhảy thẳng tới vị trí | P2 (đi cùng D8 bóng râm) |
| M5 | **Symbol vẽ ra** | Gửi report xong, tạo alert xong | `checkmark.circle` vẽ ra bằng symbol effect *Draw On* (SF Symbols 7). Thiết bị cũ hơn dùng `.symbolEffect(.bounce)` | khoảng 0.4 s | Hệ thống tự giảm | P1 (kiểm lại tên API khi code) |
| M6 | **Widget chuyển số** | Widget | `contentTransition(.numericText())` khi timeline cập nhật (WidgetKit tự animate) | hệ thống | Hệ thống | P1 |

Giới hạn chung:
- Mỗi màn tối đa **một** motion graphic đang chạy.
- Motion tự chạy chỉ được chạy một lần (M2, M3). Mọi thứ lặp lại hoặc dài (M1) phải do người dùng bấm.
- Không chặn thao tác: chạm vào đâu là motion dừng ngay và hiện trạng thái cuối.
- Hiệu năng: 60/120 fps trên iPhone 12 trở lên. Time-lapse chỉ cập nhật annotation đang *nhìn thấy*, dữ liệu 12 giờ tải sẵn trong một request.

**Đánh giá motion graphic: 8.5/10.** M1 và M2 nói đúng câu chuyện của app và không phải để làm màu. Bị trừ vì M1 cần backend trả điểm của nhiều giờ trong một lần gọi bbox (§7) và chưa đo hiệu năng với khoảng 500 pin. M5 phụ thuộc phiên bản SF Symbols.

## 9. Xếp lớp màn hình (stack) và thao tác kéo

### Điều hướng dạng stack

- Mỗi tab có một `NavigationStack` riêng, tối đa **2 lớp push**: gốc → Spot Detail → (Data Sources hoặc City list). Không push sâu hơn.
- Sheet tối đa **2 lớp chồng nhau**. Trên Map, Spot Detail đã là sheet; mở Why 82?, Report hay Alert editor từ đó là sheet lớp 2. iOS tự đẩy lớp dưới lùi ra sau, đó là hành vi chuẩn.
- Từ lớp sheet thứ 2 cần mở thêm (ví dụ Alert editor → Paywall) thì **không** mở sheet lớp 3: Paywall được push bên trong `NavigationStack` của chính sheet đó.
- Bấm lại tab đang mở: pop về gốc, rồi cuộn lên đầu (hành vi chuẩn của `TabView` + `NavigationStack`).
- **Không dùng giao diện xếp chồng thẻ** kiểu Tinder hay ví Wallet: người dùng cần *so sánh* nhiều điểm, nên danh sách cho thấy nhiều hơn một lần nhìn.

### Thao tác kéo và vuốt

| Thao tác | Ở đâu | API | Ghi chú |
|---|---|---|---|
| Kéo sheet giữa các detent | Spot Detail trên Map | `presentationDetents` | Như Apple Maps |
| Vuốt xuống để đóng sheet | Mọi sheet | mặc định | Alert editor có thay đổi chưa lưu: `.interactiveDismissDisabled(isDirty)`, bấm Cancel thì hỏi "Discard Changes?" |
| Vuốt hàng sang trái | Best Now: Save. Saved: Delete | `.swipeActions` | Delete dùng `role: .destructive` |
| **Kéo thả sắp xếp lại** | Saved > Places | `EditButton` + `.onMove` (lưu `sortIndex` trong SwiftData) | Thứ tự do người dùng chọn; Alerts không cần sắp xếp |
| Kéo trên biểu đồ giờ | Spot Detail | `chartXSelection` | Chọn giờ, có haptic |
| Pan, zoom, xoay bản đồ | Map | MapKit | Mặc định |
| Long-press | Pin, hàng, cột giờ | `.contextMenu(menuItems:preview:)` | Danh sách action ở `UI.md` |
| Kéo để làm mới | Best Now, Saved | `.refreshable` | |
| Kéo điểm sang app khác (P2) | Hàng điểm | `.draggable` + `Transferable` (link + tên) | Thả vào Messages hay Notes; app không nhận thả từ ngoài vào |

Không tự viết `DragGesture` ở đâu cả. Mọi thao tác kéo đều là của hệ thống.

## 10. Đa thiết bị: iPhone, iPad, Mac, iPhone gập

### 10.1 Quyết định nền tảng

| Câu hỏi | Đề xuất | Lý do |
|---|---|---|
| Cách làm bản Mac | **Một target SwiftUI multiplatform** (destinations: iPhone, iPad, Mac), không dùng Mac Catalyst, không dùng "Designed for iPad" | "Designed for iPad" chạy được ngay nhưng trên Mac trông và cảm như app iPad (sheet, toolbar, menu không đúng chất Mac), trái với yêu cầu native. Catalyst thêm một lớp UIKit dịch sang AppKit, hay vướng lỗi. SwiftUI native cho Mac dùng chung khoảng 95% code |
| Phiên bản tối thiểu | **iOS/iPadOS 18, macOS 15** | Có `TabView(.sidebarAdaptable)` (một code ra tab bar trên iPhone và sidebar trên iPad/Mac), `Tab` API mới, `onGeometryChange` để đo bề rộng, `.navigationTransition(.zoom)`. Cuối 2026 thì máy còn kẹt ở iOS 17 rất ít. Cần bạn chốt |
| Liquid Glass (giao diện iOS/macOS 26) | Để hệ thống tự áp lên tab bar, toolbar, sheet; **không** tự đặt nền cho toolbar hay tab bar | Nếu tự vẽ nền thì app sẽ lệch với hệ thống mới. Lệnh cấm glass tự chế (§0) vẫn giữ |
| Code riêng theo nền tảng | Chỉ ở: wrapper bản đồ (`UIViewRepresentable` / `NSViewRepresentable` bọc `MKMapView`, logic coordinator dùng chung), mở Settings hệ thống, haptic | Mọi thứ khác dùng chung; `#if os(macOS)` chỉ nằm trong những file này |

### 10.2 Layout theo bề rộng, không theo tên thiết bị

App **không bao giờ hỏi "đây là máy gì"**. Layout chọn theo `horizontalSizeClass` và bề rộng thật của cửa sổ (`onGeometryChange`). Nhờ vậy iPad Split View, Stage Manager, cửa sổ Mac kéo to nhỏ và iPhone gập/mở đều tự đúng.

| Lớp | Điều kiện | Gặp ở đâu | Layout |
|---|---|---|---|
| **Compact** | size class `.compact` | iPhone dọc và ngang, iPhone gập khi gập lại, iPad Slide Over hoặc split 1/3 | TabView 4 tab như §1–3 (Best Now, Map, Saved, Settings) |
| **Medium** | `.regular` và rộng < 1000pt | iPad dọc, iPad split 1/2 và 2/3, iPhone gập khi mở ra, cửa sổ Mac hẹp | **Explore 2 cột:** sidebar danh sách gợi ý (320pt) + bản đồ. Chọn điểm thì Spot Detail **push trong cột sidebar**, bản đồ vẫn còn bên phải |
| **Wide** | `.regular` và rộng ≥ 1000pt | iPad ngang toàn màn, cửa sổ Mac thường | **Explore 3 vùng:** sidebar gợi ý (320pt) + bản đồ + **Inspector** Spot Detail (`.inspector`, 340pt) khi đã chọn điểm |

Ở Medium và Wide, **Best Now và Map gộp thành một tab "Explore"**: danh sách và bản đồ cùng hiện, chọn bên này thì bên kia highlight theo. Như vậy lớn thì có 3 mục (Explore, Saved, Settings) và tự chuyển thành sidebar nhờ `.sidebarAdaptable`. Trên Mac, Settings nằm trong `Settings { }` scene (⌘,), không phải một tab.

```
Wide (iPad ngang, Mac)
┌──────────────┬──────────────────────────────┬────────────────┐
│ Explore      │ [When ▾] [Filter] [▸ Play]   │ Vondelpark   ✕ │
│ Saved        │                              │ Park · 1.2 km  │
│ ──────────── │      (82)      ▓▓▓▓          │ 82 Great  (◔)  │
│ Best Now     │         (12) ▓▓polygon▓ (64) │ Clear, 21°     │
│ (82) Vondel… │◀ đang chọn  ▓▓▓▓             │ [Directions]   │
│ (78) Wester… │                              │ ▁▃▅▇█▇▅▃▁      │
│ (71) Picnic… │                    ◎ ⌖       │ Amenities …    │
│   sidebar    │          bản đồ              │   inspector    │
└──────────────┴──────────────────────────────┴────────────────┘

Medium (iPad dọc, iPhone gập mở)       Compact (iPhone)
┌────────────┬──────────────────┐     ┌──────────────┐
│ ‹ Best Now │                  │     │ Best Now     │
│ Vondelpark │   (82)  ▓▓▓      │     │ (82) Vondel… │
│ 82 Great   │      ▓polygon▓   │     │ (78) Wester… │
│ [Directions│   (64)           │     │              │
│ ▁▃▅▇█▇▅▃▁  │                  │     │──────────────│
│  sidebar   │     bản đồ       │     │ ▣  ◎  ♡  ⚙   │
└────────────┴──────────────────┘     └──────────────┘
```

Sheet theo lớp:

| Sheet | Compact | Medium / Wide (iPad) | Mac |
|---|---|---|---|
| Spot Detail từ map | Sheet có detents | Không dùng sheet: push trong sidebar (Medium) hoặc Inspector (Wide) | Inspector |
| When, Filters | Sheet `.medium` | `.popover` gắn vào nút toolbar | Popover |
| Why 82?, Report | Sheet | `.popover` (Why 82?) / sheet form (Report) | Popover / sheet |
| Alert editor, Paywall | Sheet `.large` | Sheet `.formSheet`-size (`presentationSizing(.form)`) | Sheet modal |
| Onboarding | `fullScreenCover` | Sheet `.form` ở giữa màn | Cửa sổ sheet 520×640 |

### 10.3 iPhone gập ("iPhone duo")

Mình không kiểm chứng được thông số chính thức của máy này (màn trong, bản lề, API riêng), nên spec **không dựa vào bất kỳ API riêng nào của máy gập**. Lớp layout ở §10.2 tự lo:
- Gập lại thì là Compact (giống iPhone). Mở ra thì thành Medium (2 cột như iPad mini), nếu iOS báo size class `.regular`. Nếu máy vẫn báo `.compact` khi mở, app giữ TabView nhưng nội dung dùng không gian rộng hơn (hàng 2 dòng thay vì 3).
- **Gập/mở giữa chừng không mất trạng thái:** điểm đang chọn, "When", vị trí cuộn và vùng bản đồ nằm trong `@Observable AppState` và `@SceneStorage`, không nằm trong view của từng layout. Khi đổi lớp, điểm đang mở ở sheet (Compact) sẽ thành điểm đang chọn trong sidebar (Medium), và ngược lại.
- Không đặt nút hay chữ quan trọng ở giữa màn hình theo chiều ngang (phòng trường hợp có nếp gấp). Cột 320pt + bản đồ tự tránh được điều này.
- Kiểm thử thay thế khi chưa có máy: iPad mini simulator, kéo Split View từ 1/3 lên 2/3 liên tục, Stage Manager kéo cửa sổ to nhỏ. Có máy hoặc simulator chính thức thì kiểm lại.

### 10.4 Mac và iPad có bàn phím, chuột

| Mục | Làm gì |
|---|---|
| Menu bar (`.commands`) | File: New Alert ⌘N. View: Explore ⌘1, Saved ⌘2, Play Time-lapse Space. Go: Next Hour ⌘→, Previous Hour ⌘←, Now ⌘0. Edit: Find ⌘F (vào ô tìm kiếm). Refresh ⌘R |
| Phím tắt trên iPad | Cùng bộ `.keyboardShortcut` ở trên; giữ phím ⌘ thì iPadOS tự hiện danh sách |
| Con trỏ | `.hoverEffect` mặc định của hệ thống trên hàng và nút (iPad); Mac tự có hover |
| Click phải | Chính là `.contextMenu` đã có (`UI.md`), không cần làm thêm |
| Xóa | Mac không có swipe: `.onDeleteCommand` (phím Delete) + context menu |
| Làm mới | Mac không có kéo để làm mới: nút Refresh trên toolbar + ⌘R |
| Cửa sổ | Mac tối thiểu 960×640, nhớ kích thước. P2: mở một điểm ở cửa sổ riêng (`openWindow(value: spotID)`) |
| Kéo thả | Trên iPad và Mac, `.draggable` một điểm sang Notes, Mail hay Calendar có ích hơn nhiều so với trên iPhone, nên nâng **từ P2 lên P1** cho hai nền tảng này |
| Haptic | `sensoryFeedback` tự không làm gì trên Mac, không cần nhánh code riêng |
| Widget | Mac có widget trên desktop, iPad có `systemLarge`: top 5 + biểu đồ giờ hôm nay |

### 10.5 Kiểm thử bắt buộc trước mỗi release

iPhone SE (nhỏ nhất) · iPhone Pro Max · iPad mini dọc · iPad Pro 13" ngang · iPad Split View 1/3, 1/2, 2/3 · Stage Manager · Mac cửa sổ 960pt và toàn màn · máy gập (khi có) · mỗi lớp kiểm thêm Dynamic Type AX3 và dark mode.

## 11. Tự chấm

Đây là điểm cho bản spec trên giấy, chưa có ảnh chụp từ máy thật. Điểm thật chỉ có sau khi build và review trên TestFlight.

| Tiêu chí | Trọng số | Điểm | Lý do trừ điểm |
|---|---|---|---|
| Đúng chuẩn native Apple (HIG) | 15% | 9.0 | Map phải bọc `MKMapView` (UIKit) để gom cụm; vẫn chuẩn Apple nhưng phải viết thêm code nối |
| Vòng lặp chính rõ ràng (mở app → biết đi đâu) | 15% | 8.5 | Màn lớn đã gộp Best Now với Map thành Explore; trên iPhone hai tab vẫn trùng một phần, cần thử với người dùng thật |
| Chống AI slop | 10% | 9.0 | Danh sách cấm cụ thể, review được; rủi ro còn lại nằm ở lúc code (padding, bóng đổ tự thêm) |
| Màu xanh lá và nhận diện | 10% | 8.0 | Bảng màu phẳng kiểu SaaS đã đủ token (nền, chữ, thương hiệu, trạng thái, high contrast); vẫn chưa thử Meadow trên map thật (nền cỏ của Apple Maps cũng xanh, pin có thể chìm) |
| Trợ năng | 10% | 8.5 | Có VoiceOver, Dynamic Type, không chỉ dựa màu; chưa test AX5 thật |
| Hợp với dữ liệu thật | 10% | 8.5 | Xử lý được việc không có ảnh, điểm không tên, độ đông là ước lượng; thiếu polygon theo bbox |
| Độ đầy đủ so với yêu cầu | 10% | 8.5 | Đã có onboarding, animation, stack và thao tác kéo; widget, offline city pack và chỉnh trọng số điểm mới chỉ phác |
| Khả thi để code | 5% | 8.0 | Toàn API có sẵn của Apple; thêm Mac và motion graphic thì khối lượng tăng, 6 việc backend ở mục 7 |
| Đa thiết bị (iPhone, iPad, Mac, máy gập) | 10% | 8.5 | Layout theo bề rộng, không theo tên máy; trừ điểm vì chưa có thông số máy gập để kiểm, và bản đồ Mac cần wrapper riêng |
| Motion graphic | 5% | 8.5 | Vẽ dữ liệu thật, người dùng tự bật; chưa đo hiệu năng time-lapse |
| **Tổng** | | **8.55 ≈ 8.6 / 10** | Bản trước 8.6 (chỉ iPhone) |

**Rủi ro lớn nhất cần kiểm sớm:** pin màu Meadow trên nền cỏ xanh của Apple Maps. Nếu bị chìm, đổi `mapStyle` sang `.standard(emphasis: .muted)` hoặc thêm viền trắng cho glyph, nhưng **không** đổi màu thương hiệu.
