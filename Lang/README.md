# Lặng

Ứng dụng tập trung bằng tiếng Việt cho iPhone chạy iOS 17.4 trở lên. Chọn ứng dụng một lần rồi dùng cùng danh sách đó cho phiên tập trung, khung giờ lặp lại và hạn mức sử dụng mỗi ngày.

## Nếu bạn đang dùng iPhone

Tải ZIP về **Tệp** và chạm vào tệp để giải nén. Thư mục bên trong chứa mã nguồn Xcode. Để mở Lặng như một ứng dụng trên màn hình chính, bạn cần bản đã được ký cho iPhone của mình hoặc lời mời TestFlight do người phát hành tạo.

Nếu bạn dùng **ESign và chứng chỉ cá nhân**, có thể chạy bước tạo IPA trên GitHub từ Safari, sau đó ký ngay trên iPhone. Hướng dẫn đi kèm có cách lấy `Lang.ipa` và đối chiếu hồ sơ của ứng dụng cùng bốn phần mở rộng. [Cài bằng ESign](CAI-BANG-ESIGN.md)

Sau khi cài, nhấn **Bắt đầu 25 phút**, cho phép **Thời gian sử dụng**, chọn một ứng dụng thử và bấm **Lưu**. Mở ứng dụng vừa chọn để xem màn hình chặn. Nút **Kết thúc sớm** lưu thời gian thực tế của phiên.

## Chức năng

- **Tập trung** có bốn thời lượng 15, 25, 50 và 90 phút. Đồng hồ tính theo thời điểm kết thúc đã lưu, kể cả khi bạn rời Lặng.
- **Lịch chặn** có một khung giờ hằng ngày, hỗ trợ qua nửa đêm. Bạn cũng có thể đặt hạn mức dùng chung cho cả danh sách. iOS cộng thời gian dùng từ đầu ngày và kích hoạt chặn khi đủ hạn mức. Khi nhiều quy tắc trùng nhau, danh sách vẫn bị chặn chừng nào còn một quy tắc có hiệu lực.
- **Hoạt động → Phiên tập trung** hiển thị 7 ngày gần nhất cùng lịch sử các phiên bạn tự bắt đầu. Phiên qua nửa đêm được chia vào từng ngày, phiên dừng sớm chỉ tính phần đã qua.
- **Hoạt động → Dùng iPhone** hiển thị số liệu trong ngày và tối đa ba ứng dụng dùng nhiều nhất do Thời gian sử dụng cung cấp. Báo cáo được vẽ ngay trong phần mở rộng riêng tư của iOS.

## Chạy dự án trên máy thật

1. Trên Mac có Xcode 16 trở lên và SDK hỗ trợ phiên bản iOS trên máy thử, mở **Lang.xcodeproj**. Dự án dùng các framework có sẵn của Apple.
2. Trong **Config/Signing.xcconfig**, đổi `LANG_BUNDLE_BASE` thành mã ứng dụng riêng của bạn và điền Team ID vào `LANG_TEAM`. `LANG_APP_GROUP` mặc định bằng `group.` ghép với mã ứng dụng đó.
3. Đăng nhập đội Apple Developer có quyền dùng Family Controls. Ở **Signing & Capabilities**, giữ **Automatically manage signing** và kiểm tra quyền theo bảng bên dưới. Đăng ký App Group trong tài khoản của đội và gắn đúng nhóm cho hai target dùng chung dữ liệu.
4. Chọn scheme **Lang**, chọn iPhone làm thiết bị chạy, rồi bấm **Run ▶**. Bật Developer Mode trên iPhone nếu Xcode yêu cầu.

| Target | Nhiệm vụ | Quyền |
| --- | --- | --- |
| Lang | Giao diện và cấu hình | Family Controls, App Groups |
| LangMonitor | Bắt đầu, kết thúc lịch và nhận sự kiện hết hạn mức | Family Controls, cùng App Group với Lang |
| LangShield | Hiển thị màn hình chặn | Family Controls |
| LangAction | Xử lý nút Đóng trên màn hình chặn | Family Controls |
| LangReport | Hiển thị thời gian dùng iPhone | Family Controls |

Muốn phân phối qua TestFlight hoặc App Store, chủ tài khoản nhà phát triển cần xin **Family Controls (Distribution)** cho các App ID của ứng dụng và các phần mở rộng ở trên. Sau khi được cấp quyền và có hồ sơ ký phù hợp, mở **Product → Archive → Distribute App** trong Xcode. [Hướng dẫn của Apple](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

## Kiểm thử

Trong Xcode, chọn scheme **Lang**, chọn một iPhone Simulator và nhấn **⌘U** để chạy các bài kiểm tra phiên, hạn mức, quy tắc trùng nhau và thống kê qua nửa đêm. Để kiểm tra riêng phần tính thời gian trên macOS hoặc Linux, chạy từ thư mục chứa README này.

```sh
cc -std=c11 -Wall -Wextra -Werror Shared/FocusMath.c Tests/focus_math_test.c -lm -o /tmp/lang-math-test
/tmp/lang-math-test
```

Để thử việc chặn thật, trên iPhone chọn một ứng dụng, bắt đầu phiên rồi thoát Lặng. Mở ứng dụng đó để kiểm tra. Thử thêm một lịch đang có hiệu lực, kết thúc phiên và kiểm tra ứng dụng còn bị chặn theo lịch. Khi tắt lịch cuối cùng và còn hạn mức, ứng dụng sẽ mở lại. iOS có thể chuyển trạng thái lịch ở lần đầu dùng máy trong hoặc sau khung giờ. [Tài liệu Device Activity](https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval)
