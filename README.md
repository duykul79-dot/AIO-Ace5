# AIO Ace5

**AIO Ace5** là module tuỳ biến dành cho **OnePlus Ace 5 / PKG110** chạy nền **ColorOS / OPlus**, hỗ trợ các môi trường root như **KernelSU**, **Magisk** và **APatch**.

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

- Thiết bị: **OnePlus Ace 5**
- Model: **PKG110**
- Nền tảng: **ColorOS / OPlus**
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

Module có thành phần Zygisk trong thư mục:

```text
zygisk/