# Pickhour — Roadmap

*Cập nhật 2026-11-13 · áp dụng cho cả app (`pickhour-app`) và backend (`pickhour-backend`)*

Nguyên tắc: **ra mắt và đo giữ chân trước, tính năng lớn sau.** Mỗi giai đoạn có một "cổng" bằng số liệu; chưa qua cổng thì không mở giai đoạn sau.

Ước lượng công sức tính bằng **ngày làm việc của 1 dev có AI hỗ trợ**, chỉ để so sánh tương đối, chưa tính review và QA trên máy thật. Cột "Phần" ghi việc nằm ở App, BE (backend) hay Ops.

Liên quan: `docs/UI_SPEC.md` (màn hình), `../Yêu cầu hệ thống App Picnic.md` (ID yêu cầu F/D, §15 thu phí, §16 độ đông), `pickhour-backend/docs/API.md`, `pickhour-backend/docs/INGEST_STRATEGY.md`.

---

## Trạng thái hiện tại (2026-11-13)

| Hạng mục | Trạng thái |
|---|---|
| Dữ liệu | 39 city pack, 18 nước, 15.091 điểm đang hiện; prod seed từ cloud dump |
| Backend API cho UI | Xong: weatherSource, spots theo ids, điểm nhiều giờ, polygon, packs, ngày lễ, bộ lọc (commit `48ab039`, `87f3865`, `495dae9` trên `dev`, chưa push) |
| Worker image | Có osmium-tool (`--target worker`) |
| App UI | Đã viết: onboarding, Best Now, Map (cụm, polygon, time-lapse), Spot Detail, Why 82?, Report, Saved, Alerts, Filters, Settings, Paywall, layout iPad/Mac. **Chưa compile, chưa commit** |
| Nền tảng | iPhone, iPad, Mac native (macOS 15) trong cùng target |

---

## Gói Free / Plus

Quyền lợi từng gói, giá và lúc hiện paywall: xem `../Yêu cầu hệ thống App Picnic.md` §15. Tóm tắt: chỉ 2 bậc Free và Plus. Ra mắt với $14,99/năm, $2,99/tháng, dùng thử 7 ngày; khi có bóng râm và gói ngoại tuyến thì nâng lên $19,99/năm cho người mới.

---

## Giai đoạn 0 — Ra mắt (TestFlight → App Store)

Mục tiêu: một bản chạy được, đúng pháp lý, đủ để đo.

| # | Việc | Phần | Công | Phụ thuộc |
|---|---|---|---|---|
| 0.1 | Compile app iOS + Mac, sửa lỗi build, bật lại CI | App | 1–2 | — |
| 0.2 | Kiểm UI trên máy thật theo danh sách ở UI_SPEC §10.5 (Dynamic Type AX3, dark mode, iPad split, cửa sổ Mac) | App | 2 | 0.1 |
| 0.3 | Icon thật (Icon Composer), đổi bundle ID khỏi `com.example`, App ID bật Mac + Push | App | 1 | — |
| 0.4 | Tạo sản phẩm Plus trên App Store Connect, khớp `PaywallSheet.productIDs` | App | 0.5 | 0.3 |
| 0.5 | Chính sách riêng tư, nhãn quyền riêng tư App Store, điều khoản | Ops | 1 | — |
| 0.6 | Push 3 commit backend, deploy API + worker, restore cloud dump vào prod | BE/Ops | 1–2 | — |
| 0.7 | Giám sát: cảnh báo khi job lỗi hoặc dữ liệu cũ (`/v1/admin/freshness`) | BE/Ops | 1 | 0.6 |
| 0.8 | ~~Ghi điểm theo lô cho `scoring` và `crowd.refresh`~~ **Xong** (`334dd59`, `7aa5846`): tính lại toàn bộ 15k điểm mất 251 s (trước khoảng 4,4 h), lần chạy không có gì đổi mất 112 s; crowd 40 s (trước khoảng 3,9 h) | BE | — | — |
| 0.9 | Alert theo khu vực: backend nhận `lat/lon/radiusM` và tự tính H3, app thêm lựa chọn "Area around…" | BE + App | 1.5 | BE `63c854e` (`area {lat,lon}` + `radiusM`, H3 res 7); app: Saved › Alerts › Add Area Alert. Chưa compile |
| 0.10 | Báo độ đông khi ở gần (S9, kiểm khoảng cách trên máy) | App | 1 | Đã viết: mục "How busy is it right now?" trong Spot Detail khi ở gần (park/beach 600 m, site/table 150 m). Chưa compile |
| 0.11 | Widget nhỏ và vừa + Lock Screen (D7) | App | 2–3 | Đã viết: target `PickhourWidget` (small, medium; Lock Screen trên iOS), App Group `group.com.example.MyApp`. Chưa compile |
| 0.12 | Kéo thả điểm sang app khác (`.draggable` + `Transferable`) trên iPad/Mac | App | 0.5 | Đã viết: kéo hàng điểm ra thành link Apple Maps. Chưa compile |
| 0.13 | Xử lý spot bị gộp trong Saved: backend trả kèm id gốc khi resolve | BE + App | 0.5 | — |
| 0.15 | Free: dải 7 ngày (mỗi ngày 1 điểm tổng + giờ đẹp nhất), chỉ khóa chi tiết theo giờ từ ngày 3; paywall mở khi chạm vào phần khóa (Yêu cầu §15) | App | 1 | Đã viết: `WeekStrip` thay picker ngày. Chưa compile |
| 0.16 | Kế hoạch tuần (Plus): mục "This Week" trong Saved và sidebar iPad/Mac | App | 1 | — (đã viết, chưa compile) |
| 0.17 | Khảo sát khi đóng paywall (`paywall_feedback`) + truy vấn đếm phía admin | App + BE | 0.5 | — (đã viết, chưa compile) |
| 0.18 | Thông báo kế hoạch cuối tuần tối thứ 5 (Plus): `PUT /v1/devices/{id}/digest`, job `digest.weekly` | BE + App | 1.5 | — (BE commit `039f239`, app đã viết; chưa compile) |
| 0.14 | TestFlight cho khoảng 20 người, ở 1–2 thành phố | Ops | — | 0.1–0.7 |

**Tổng: khoảng 15–20 ngày.** Các mục 0.9–0.13 có thể dời sang sau TestFlight nếu cần ra sớm.

**Cổng sang giai đoạn 1:** sau 2 tuần TestFlight có ≥ 30% người dùng quay lại lần hai, và không có lỗi crash hay dữ liệu sai nghiêm trọng.

---

## Giai đoạn 1 — Sau ra mắt: tăng giá trị và chuyển đổi

Thứ tự trong bảng là thứ tự đề xuất. Cột "Làm khi" cho biết số liệu nào đẩy mục đó lên trước.

| # | Việc | Phần | Công | Gói | Làm khi |
|---|---|---|---|---|---|
| 1.1 | **Đa ngôn ngữ v1:** de, fr, es, it, nl (String Catalog, bảng thuật ngữ picnic) | App | 3 | Free | Có người dùng ngoài nước nói tiếng Anh |
| 1.2 | **Siri, Shortcuts, App Intents:** "Hôm nay đi công viên nào?" | App | 2 | Free | Giữ chân thấp, cần thêm điểm chạm |
| 1.3 | **Độ đông cộng đồng (D9):** gộp báo cáo, hiệu chỉnh mô hình §16, đổi nhãn nguồn | BE + App | 4–5 | Free | Đủ báo cáo ở ít nhất 1 thành phố |
| 1.4 | **Bóng râm / nắng (D8):** vị trí mặt trời + nhà/cây OSM, thành phần `shade`, motion "đường mặt trời" (M4). Kế hoạch chi tiết: `pickhour-backend/docs/SHADE_PLAN.md`, benchmark Amsterdam trước | BE + App | 6–8 | Plus | Chuyển đổi Plus thấp |
| 1.5 | **Cá nhân hóa trọng số:** kids/dog/nóng, chỉnh trong Settings | BE + App | 3 | Plus | Chuyển đổi Plus thấp |
| 1.6 | **Gói thành phố offline:** tải trước điểm + 7 ngày điểm số | BE + App | 4 | Plus | Có phản hồi mất sóng ở công viên hoặc bãi biển |
| 1.7 | **Thêm thành phố:** thêm vào `scripts/ingest/packs.tsv` theo nơi có người tải | BE/Ops | 0.5/thành phố | Free | Có lượt tải từ thành phố chưa phủ |
| 1.8 | **Đồng bộ yêu thích qua iCloud** (SwiftData + CloudKit) | App | 2 | Plus | Có người dùng nhiều thiết bị, hoặc nhiều phiếu "sync" trong khảo sát paywall |
| 1.9 | **Widget theo tuần, nhiều khu vực** | App | 1.5 | Plus | Sau 0.11 |
| 1.10 | **Hiệu chỉnh điểm số** từ phản hồi "Is this score right?" (cấu hình chấm điểm có phiên bản) | BE | 2 | — | Có ≥ 200 phản hồi |

**Cổng sang giai đoạn B (độ đông trả phí):** doanh thu ròng hằng tháng ≥ chi phí BestTime (khoảng 170–200 USD/tháng, yêu cầu §15).

| # | Việc | Phần | Công |
|---|---|---|---|
| 1.B | **BestTime cho vài chục công viên lớn nhất**, nhãn nguồn riêng, không trộn lẫn âm thầm với dữ liệu mô hình (§16) | BE | 3 |

---

## Giai đoạn 2 — v2 (dài hạn)

| # | Việc | Ghi chú |
|---|---|---|
| 2.1 | Lập kế hoạch nhóm, danh sách đồ mang (D10) | Cần tài khoản (Sign in with Apple), tăng gánh nặng riêng tư |
| 2.2 | Lớp quy định theo nơi: BBQ, rượu bia, chó (D11) | Phải kiểm chứng từng thành phố; rủi ro sai lệch pháp lý |
| 2.3 | Apple Watch: điểm hiện tại, nhận alert | Dùng lại widget/App Intents |
| 2.4 | Android / web dùng MapLibre | Chỉ khi iOS đã có lãi; cần tile riêng (PMTiles trên R2) |
| — | Không làm bậc thứ ba (Pro). Tính năng mới đắt hơn vẫn vào Plus, có thể tăng giá Plus khi đủ giá trị | Quyết định 2026-11-13 |

---

## Chỉ số theo dõi

| Chỉ số | Nguồn | Dùng để quyết |
|---|---|---|
| Quay lại lần hai trong 2 tuần | `POST /v1/events` (`spot_opened`, phiên) | Cổng giai đoạn 0 → 1; có nên kéo 1.2 lên sớm |
| Paywall → dùng thử → trả phí | `paywall_shown`, `plus_purchased`, App Store | Ưu tiên 1.4, 1.5, 1.6 |
| Lý do không mua (khảo sát paywall) | `paywall_feedback`, `GET /v1/admin/events/breakdown?name=paywall_feedback&prop=choice` | Thứ tự giai đoạn 1 (bóng râm, ngoại tuyến, trọng số, iCloud); giá có quá cao không |
| Bộ lọc dùng nhiều nhất | `filters_applied` | Thứ tự tiện ích, chỉnh trọng số |
| Alert tạo / giao | `alert_created`, `t_alert_deliveries` | Giá trị của thông báo |
| Phản hồi điểm (đúng / cao / thấp) | `t_score_feedbacks` | 1.10 |
| Báo cáo độ đông theo thành phố | `t_crowd_reports` | Thời điểm bật 1.3 |
| Lượt tải theo thành phố chưa phủ | App Store Analytics | 1.7 |

---

## Rủi ro chính

- **Mùa vụ:** Mỹ và châu Âu vào đông thì Úc vào hè; tập trung marketing và thêm thành phố ở Úc từ tháng 11 đến tháng 3.
- **Dữ liệu OSM không đều:** theo dõi tỷ lệ báo cáo "It's gone" theo thành phố; thành phố nào có tỷ lệ cao thì đưa vào danh sách kiểm tra trong `INGEST_STRATEGY.md`.
- **Chi phí độ đông:** chỉ bật 1.B khi qua cổng doanh thu.
- **Điều khoản WeatherKit, BestTime:** kiểm lại quyền lưu cache và hiển thị trước khi mở rộng.
