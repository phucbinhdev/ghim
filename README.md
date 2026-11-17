# Ghim 📌

Ghi chú & việc cần làm ghim ở cạnh màn hình macOS. Native (SwiftUI + AppKit), không cần tài khoản, dữ liệu nằm ở `~/Library/Application Support/Ghim/data.json`.

## Build
```bash
./scripts/build_app.sh        # → build/Ghim.app
cp -R build/Ghim.app /Applications/
```

## Dùng nhanh
- Dải tab màu nằm ở cạnh phải, mờ khi không dùng; rê chuột vào là rõ lên, bấm tab để mở.
- Kéo tay nắm ≡ ở đầu dải để đổi vị trí. Đổi cạnh/độ mờ trong Cài đặt.
- ⌃⌥Space mở/đóng · ⌃⌥N ghi nhanh · ⌃⌥T tab Hôm nay.
- Cú pháp: `Gọi mẹ #family @mai @9h !! ~15m /weekly`
- Ảnh trong ghi chú: ⌘V ảnh/screenshot (⌃⇧⌘4), kéo thả file ảnh vào thẻ, vào tab Notes, hoặc ⌘V trong ô ghi nhanh. Nhấp đúp ảnh để mở, kéo ảnh ra app khác để gửi.
- Đổi kích thước panel: kéo cạnh ngoài (rộng), cạnh dưới (cao) hoặc góc dưới (cả hai). Nhấp đúp vào mép hoặc bấm nút ⤢ trên header để phóng to / thu nhỏ.
