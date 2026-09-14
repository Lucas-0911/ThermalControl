# Cài Thermal Control (người nhận)

Bạn được gửi file **`ThermalControl-1.0.0.pkg`**. Đây là bộ cài macOS (không phải `.dpkg` của Linux).

## Cài

1. Double-click `ThermalControl-1.0.0.pkg`.
2. Nếu báo không mở được:
   - Chuột phải file → **Open** → Open.
3. Làm theo installer, nhập **mật khẩu máy** khi được hỏi (cần để cài helper điều khiển quạt/pin).
4. Mở **Launchpad** hoặc **Applications** → **Thermal Control**.
5. Click icon quạt trên thanh menu.

## Dùng nhanh

- **Quạt:** Auto / Êm / Max / Custom
- **Pin:** Full hoặc Giới hạn (dừng sạc ở %)
- Trong cửa sổ app: chọn ngôn ngữ, bật **Mở cùng máy** nếu muốn tự chạy lúc mở Mac

## Gỡ

Kéo app vào Thùng rác **chưa đủ**. Cần gỡ helper:

Liên hệ người gửi để lấy `Scripts/uninstall_helper.sh`, rồi:

```bash
sudo bash uninstall_helper.sh
rm -rf "/Applications/Thermal Control.app"
```

## Yêu cầu

macOS 14 trở lên. Mac mini / Studio không có pin nội bộ — chỉ dùng quạt (nếu máy có quạt).
