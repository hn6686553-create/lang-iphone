# Cài Lặng bằng chứng chỉ cá nhân trên iPhone

Nếu đã có **Lang.ipa**, đi thẳng đến bước 3. ESign ký bản IPA đã biên dịch. ZIP mã nguồn dùng cho bước 2.

## 1. Đối chiếu hồ sơ ký

Trong tài khoản của đội Apple Developer, các App ID và hồ sơ cấp phép bên dưới phải khớp chứng chỉ dùng để ký và cho phép cài lên iPhone của bạn. Với hồ sơ Development hoặc Ad Hoc, iPhone cần nằm trong danh sách thiết bị đã đăng ký. App Store distribution là hồ sơ dành cho luồng phát hành qua Apple.

Gọi Bundle ID chính đã đăng ký của bạn là `B`. Khi chạy build, thay `B` bằng tên thực tế. Ví dụ nếu dùng `vn.tenban.lang` thì ID của bộ theo dõi là `vn.tenban.lang.monitor`.

| Thành phần | Bundle ID cần khớp | Quyền trong hồ sơ |
| --- | --- | --- |
| Lặng | `B` | Family Controls và App Groups |
| Theo dõi thời gian | `B.monitor` | Family Controls và cùng App Group với Lặng |
| Màn hình chặn | `B.shield` | Family Controls |
| Nút đóng | `B.action` | Family Controls |
| Báo cáo | `B.report` | Family Controls |

Hai khóa Apple tương ứng là `com.apple.developer.family-controls` và `com.apple.security.application-groups`. Một chứng chỉ có thể dùng để ký nhiều thành phần khi các hồ sơ tương ứng cấp đủ quyền. Người dùng hồ sơ mua hoặc được cấp sẵn có thể nhờ người quản lý đội kiểm tra hai quyền. Đối với bản ký Ad Hoc, kiểm tra Family Controls đã được Apple cấp cho đúng phương thức phân phối và từng App ID. [Hồ sơ ký của Apple](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) · [Quyền Family Controls](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

## 2. Tạo IPA từ Safari bằng GitHub Actions

Trong kho đã có workflow **Tạo IPA Lặng**, bắt đầu từ bước 3. Nếu đã có lần chạy thành công với đúng Bundle ID và App Group, chuyển thẳng đến bước 4. Các bước 1–2 dành cho kho mới.

1. Tạo một kho GitHub **Private** với **Add README** được bật. Tải bản **Lang-iPhone.zip** đi kèm hướng dẫn này lên ngay trang đầu của kho bằng **Add file → Upload files → Commit changes**. Tải nguyên tệp ZIP lên.
2. Trong ứng dụng Tệp của iPhone, chạm vào ZIP để giải nén một bản trên máy. Mở **Lang → Build → tao-ipa.yml** và sao chép toàn bộ nội dung. Trên GitHub, chọn **Add file → Create new file**, điền tên `.github/workflows/tao-ipa.yml`, dán nội dung đó rồi chọn **Commit changes** vào nhánh mặc định.
3. Mở **Actions → Tạo IPA Lặng → Run workflow**. Điền Bundle ID chính và App Group trùng với hồ sơ ký. Nếu đã đăng ký App Group là `group.` ghép với Bundle ID chính, có thể bỏ trống ô App Group. Bấm **Run workflow**.
4. Khi lần chạy có dấu tích xanh, mở lần chạy và tải **Lang.ipa** trong **Artifacts** về Tệp trên iPhone. Nếu lần chạy báo lỗi, mở bước **Biên dịch cho iPhone** để xem dòng lỗi. GitHub thực hiện biên dịch trên macOS. Chứng chỉ, hồ sơ và mật khẩu của bạn vẫn ở trên iPhone. [Chạy workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) · [Tải kết quả](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

Nếu đã có kho chứa thư mục dự án được giải nén, chỉ cần đặt `tao-ipa.yml` ở `.github/workflows/tao-ipa.yml` trên nhánh mặc định. Workflow cũng nhận thư mục dự án trực tiếp. Nếu dùng máy Mac có Xcode, từ thư mục chứa `Lang.xcodeproj` có thể chạy lệnh sau với hai mã đã đăng ký của bạn.

```sh
python3 Build/build_ipa.py --bundle-id vn.tenban.lang --app-group group.vn.tenban.lang --output Lang.ipa
```

## 3. Ký trên iPhone

1. Trong ESign, vào **Tệp → Nhập**, chọn **Lang.ipa**, rồi chọn nhập vào danh sách ứng dụng nếu được hỏi.
2. Vào **Ứng dụng**, chọn **Lặng → Ký**. Chọn chứng chỉ của bạn và các hồ sơ khớp Bundle ID ở bảng trên. Giữ lại cả bốn phần mở rộng cùng quyền của chúng. Tùy phiên bản, tên nút và khả năng gán hồ sơ cho từng phần mở rộng có thể khác nhau. Khi công cụ ký chỉ áp dụng một hồ sơ chung và bỏ quyền của phần mở rộng, hãy dùng trình ký hỗ trợ gán hồ sơ theo từng Bundle ID hoặc xuất bản đã ký bằng Xcode.
3. Sau khi ký xong, chọn **Cài đặt**. Mở **Lặng**, chọn **Bắt đầu 25 phút**, cho phép **Thời gian sử dụng**, chọn một ứng dụng rồi bấm **Lưu**. Mở ứng dụng vừa chọn để thử màn hình chặn.

Nếu có lỗi quyền khi cài, đối chiếu Bundle ID, danh sách thiết bị và các quyền trong hồ sơ ký của từng thành phần. Nếu mở được Lặng nhưng không cấp được quyền Thời gian sử dụng, kiểm tra Family Controls trong cả hồ sơ lẫn chữ ký cuối cùng. Hãy giữ file `.p12` và mật khẩu riêng trên thiết bị của bạn.
