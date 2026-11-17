# Ghim 📌

Ghi chú & việc cần làm **ghim ở cạnh màn hình macOS** — như những mảnh giấy note dán bên mép màn hình, mờ đi khi không dùng, rê chuột vào là rõ, bấm là mở.

App native (SwiftUI + AppKit), không cần tài khoản, không gửi dữ liệu đi đâu. Dữ liệu nằm ở `~/Library/Application Support/Ghim/`.

## Tính năng
- **Dải tab màu** ở cạnh trái/phải màn hình, mờ khi không dùng (chỉnh độ mờ được), kéo tay nắm ≡ để đổi vị trí.
- **Tab tuỳ chỉnh**: danh sách việc (có checkbox) hoặc ghi chú tự do; đổi tên, màu, thứ tự.
- **Hôm nay**: tiến độ trong ngày, chuỗi ngày 🔥, phút tập trung, gợi ý việc nên làm.
- **Gõ nhanh có cú pháp**: `Gọi mẹ #family @mai @9h !! ~15m /weekly`.
- **Pomodoro**: bấm ▶ trên một việc để tập trung, đồng hồ hiện ngay trên dải tab.
- **Ghi chú có ảnh**: ⌘V ảnh/screenshot, kéo thả file ảnh, kéo ảnh ra app khác để gửi.
- **Việc lặp lại** (hằng ngày / T2–T6 / hằng tuần), nhắc giờ bằng thông báo.
- **Panel kéo giãn được**, có chế độ phóng to; tìm kiếm mọi tab; xuất Markdown.
- **Phím tắt toàn hệ thống**: `⌃⌥Space` mở/đóng · `⌃⌥N` ghi nhanh · `⌃⌥T` tab Hôm nay.

## Cài đặt
Yêu cầu macOS 14 trở lên và Xcode hoặc Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/phucbinhdev/ghim.git
cd ghim
./scripts/build_app.sh          # → build/Ghim.app
cp -R build/Ghim.app /Applications/
```

## Cú pháp gõ nhanh
| Gõ | Ý nghĩa |
|---|---|
| `#family` | đưa vào tab Family (gõ vài chữ đầu là đủ) |
| `!` `!!` `!!!` | ưu tiên thấp / vừa / cao |
| `@nay` `@mai` `@kia` `@t2`…`@cn` `@20/11` `@+3` | hạn |
| `@15h` `@9:30` `@3pm` | giờ (có thông báo nhắc) |
| `~30m` `~1h` | ước lượng thời gian (nút ▶ dùng số phút này) |
| `/daily` `/weekdays` `/weekly` | lặp lại |
| `*` | đưa vào Hôm nay |

## Phát triển
```bash
swift build && .build/debug/Ghim                 # chạy bản debug
GHIM_DATA_DIR=/tmp/ghim-test .build/debug/Ghim   # dùng thư mục dữ liệu riêng để thử
.build/debug/Ghim --snapshot /tmp/shots          # render các màn hình ra PNG rồi thoát
```

Code chính trong `Sources/Ghim/`:
- `PanelController.swift` — cửa sổ cạnh màn hình, mở/thu gọn, độ mờ, kéo giãn
- `RootView.swift` — dải tab · `ContentPanel.swift` — panel nội dung
- `TaskViews.swift`, `OtherViews.swift`, `NoteImages.swift` — việc, Hôm nay, ghi chú, ảnh
- `Store.swift`, `Models.swift` — dữ liệu & lưu JSON · `QuickParser.swift` — cú pháp gõ nhanh

Cứ fork và sửa thoải mái. Pull request luôn được chào đón 🙌

## Giấy phép
[MIT](LICENSE)
