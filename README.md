# AIO Ace5

**AIO Ace5** là module tuỳ biến dành cho **OnePlus Ace 5/13R** chạy nền **ColorOS / OxygenOS**, hỗ trợ các môi trường root như **KernelSU**, **Magisk** và **APatch**.

Module tập trung vào các nhóm tính năng chính: **Debloat**, **Dọn rác**, **Pin**, **Hiệu năng**, **WebUI**, **Realtime Log**, **Zygisk component** và hỗ trợ xuất log/report để tiện kiểm tra, audit hoặc báo lỗi.

> Author / Telegram: **@keobamien**  
> Credits: **Copg+ Extreme**

English version: [README.en.md](README.en.md)

---

## Tổng quan

AIO Ace5 được xây dựng để gom các tác vụ tối ưu thường dùng trên thiết bị root vào một giao diện WebUI gọn gàng, dễ dùng và dễ kiểm soát.

Mục tiêu chính:

- Giảm app/dịch vụ thừa.
- Dọn cache/rác hệ thống thuận tiện hơn.
- Theo dõi báo cáo pin dễ đọc hơn.
- Tối ưu một số tác vụ hiệu năng, game, sạc và cảm ứng.
- Hỗ trợ thành phần Zygisk cho các tính năng phụ thuộc môi trường root.
- Theo dõi tiến trình thao tác bằng log thời gian thực.
- Hỗ trợ xuất log/report để tiện kiểm tra và audit.
- Giữ trải nghiệm sử dụng đơn giản, rõ ràng, dễ kiểm tra.

---

## Thiết bị mục tiêu

Module được phát triển chủ yếu cho:

- Thiết bị: **OnePlus Ace 5/13R**
- Model: **PKG110**
- Nền tảng: **ColorOS / OxygenOS**
- Root: **KernelSU / Magisk / APatch**
- Kiến trúc: **arm64-v8a**

Các thiết bị hoặc ROM khác có thể không tương thích hoàn toàn.

---

## Yêu cầu trước khi dùng

Khuyến nghị môi trường sử dụng:

- Thiết bị đã root bằng **KernelSU**, **Magisk** hoặc **APatch**.
- Nên bật **Zygisk** nếu môi trường root có hỗ trợ.
- Nên khởi động lại máy sau khi bật Zygisk.
- Nên khởi động lại máy sau khi flash module.
- Nên dùng đúng nền **ColorOS / OPlus** cho OnePlus Ace 5 / PKG110.
- Nên giữ một bản module ổn định để rollback khi cần.

### Lưu ý về Zygisk

Module có thành phần Zygisk trong thư mục `zygisk/`.

Một số tính năng như **game spoof**, compatibility layer hoặc các phần phụ thuộc Zygisk có thể không hoạt động đầy đủ nếu Zygisk chưa được bật.

Nếu dùng KernelSU, APatch hoặc Magisk, hãy kiểm tra phần cài đặt của trình quản lý root và bật Zygisk nếu có tuỳ chọn tương ứng.

---

## Tính năng chính

### 1. Debloat

Tab **Debloat** hỗ trợ xử lý các package không cần thiết theo danh sách có sẵn.

Mục tiêu:

- Giảm app/dịch vụ không cần thiết.
- Giảm tác vụ nền không mong muốn.
- Giữ thao tác có kiểm soát qua WebUI.
- Hạn chế rủi ro bằng cách phân nhóm package rõ ràng.
- Không tự động chạy debloat ngầm ngoài ý muốn.

Lưu ý: Debloat có thể ảnh hưởng đến ứng dụng hoặc dịch vụ hệ thống. Người dùng nên đọc kỹ mô tả trong WebUI trước khi chạy.

### 2. Dọn rác

Tab **Dọn rác** hỗ trợ hai chế độ:

- **Dọn nhanh**: xử lý nhanh các vùng cache/rác an toàn.
- **Dọn toàn bộ**: quét sâu hơn, thời gian chạy có thể lâu hơn.

Sau khi chạy **Dọn nhanh** hoặc **Dọn toàn bộ** thành công, WebUI sẽ hiển thị popup khuyến nghị khởi động lại thiết bị để hệ thống giải phóng tài nguyên và hoạt động ổn định hơn.

### 3. Pin

Tab **Pin** hỗ trợ tạo báo cáo pin và hiển thị thông tin phục vụ kiểm tra tình trạng pin.

Mục tiêu:

- Thu thập thông tin pin cần thiết.
- Hiển thị kết quả dễ đọc trong WebUI.
- Giảm việc phải đọc log thô thủ công.
- Hỗ trợ người dùng đánh giá nhanh tình trạng sử dụng pin.
- Hỗ trợ kiểm tra nhanh dung lượng pin, mức dùng pin và các tác vụ liên quan.

### 4. Hiệu năng

Tab **Hiệu năng** tập trung vào các tuỳ chọn tối ưu sử dụng thực tế.

Tuỳ phiên bản, nhóm tính năng có thể gồm:

- Game Max
- Sạc Max
- 360Hz Touch
- Game spoof / game profile
- Một số tuỳ chọn tối ưu hệ thống liên quan

Một số thay đổi hiệu năng có thể cần khởi động lại thiết bị để áp dụng đầy đủ.

### 5. Realtime Log

Module có giao diện **Nhật ký thời gian thực** để theo dõi tiến trình thao tác ngay trong WebUI.

Ở bản v3.1.3:

- Thiết kế lại UI log cho gọn và đồng bộ hơn.
- Loại bỏ khung log cũ bị trùng trong tab Dọn rác.
- Giữ lại card log mới dễ đọc hơn.
- Không thay đổi backend log/export.
- Giúp người dùng theo dõi tiến trình tốt hơn khi chạy tác vụ.

### 6. Report / Log Export

Module hỗ trợ ghi log và report để tiện kiểm tra, audit hoặc báo lỗi.

Tuỳ tính năng, log có thể được ghi trong các thư mục tạm của hệ thống hoặc xuất ra bộ nhớ trong. Khi báo lỗi, nên gửi kèm ảnh chụp màn hình và log liên quan để dễ kiểm tra.

---

## Phiên bản hiện tại

**AIO Ace5 v3.1.3**

Thay đổi nổi bật:

- Đổi hiển thị tác giả thành **@keobamien**.
- Thiết kế lại giao diện realtime log.
- Xoá khung realtime log cũ bị trùng trong tab Dọn rác.
- Thêm popup khuyến nghị reboot sau khi chạy Dọn nhanh / Dọn toàn bộ thành công.
- Bổ sung ghi chú rõ hơn về yêu cầu Zygisk.
- Giữ nguyên backend logging/export.
- Giữ nguyên logic chính của Debloat, Dọn rác, Pin và Hiệu năng.

---

## Cài đặt

1. Tải file `.zip` từ mục **GitHub Releases**.
2. Kiểm tra SHA256 nếu có file `.sha256` đi kèm.
3. Flash module bằng KernelSU, Magisk hoặc APatch.
4. Khởi động lại thiết bị sau khi flash.
5. Bật Zygisk nếu môi trường root có hỗ trợ và module/tính năng yêu cầu.
6. Khởi động lại thêm một lần nếu vừa bật Zygisk.
7. Mở WebUI của module trong trình quản lý root/module.
8. Sử dụng từng tab theo nhu cầu.

---

## Gỡ cài đặt

Có thể gỡ module từ KernelSU, Magisk hoặc APatch.

Sau khi gỡ, nên khởi động lại thiết bị để hệ thống trở về trạng thái ổn định.

---

## Cấu trúc repo

```text
workspace_v3_1
├─ docs
│  └─ CHANGELOG.md
├─ input
├─ output
├─ work
│  └─ AIO_Ace5_v3_1_3_work
├─ README.md
├─ README.en.md
└─ .gitignore
```

Trong đó:

- `work/AIO_Ace5_v3_1_3_work/`: source module chính.
- `output/`: nơi chứa file zip đóng gói để flash.
- `input/`: nơi lưu zip gốc hoặc file đầu vào.
- `docs/`: tài liệu thay đổi và ghi chú phát triển.

---

## Release

File flash chính thức nên tải từ tab **Releases**, không lấy trực tiếp từ source tree.

Mỗi release nên có:

- File `.zip`
- File `.sha256`
- Ghi chú thay đổi
- Số phiên bản rõ ràng

Khuyến nghị luôn kiểm tra SHA256 trước khi flash.

---

## Báo lỗi

Khi báo lỗi, nên cung cấp:

- Phiên bản module.
- Thiết bị và ROM đang dùng.
- Môi trường root: KernelSU, Magisk hoặc APatch.
- Trạng thái Zygisk: bật hay tắt.
- Ảnh chụp lỗi.
- Log nếu có.
- Các bước để tái hiện lỗi.

---

## Cảnh báo

Module can thiệp vào môi trường hệ thống trên thiết bị đã root. Việc sử dụng sai cách có thể gây lỗi ứng dụng, lỗi dịch vụ hệ thống, hao pin, nóng máy hoặc bootloop.

Người dùng tự chịu trách nhiệm khi flash và sử dụng module.

Khuyến nghị:

- Sao lưu dữ liệu quan trọng trước khi dùng.
- Không flash nếu không hiểu rõ rủi ro.
- Không dùng trên thiết bị hoặc ROM chưa được kiểm tra.
- Luôn giữ một bản module ổn định để rollback khi cần.
- Không bật/tắt nhiều tính năng liên tiếp nếu chưa hiểu rõ tác dụng.
- Sau các tác vụ lớn như cleanup, debloat hoặc bật tính năng hiệu năng, nên reboot để hệ thống ổn định hơn.

---

## Credits

- Author / Telegram: **@keobamien**
- Credits: **Copg+ Extreme**

---

## Disclaimer

Module được cung cấp với mục đích cá nhân, kiểm thử và tuỳ biến thiết bị đã root. Tác giả không chịu trách nhiệm cho bất kỳ hư hỏng, mất dữ liệu, lỗi hệ thống hoặc rủi ro nào phát sinh từ việc sử dụng module.
