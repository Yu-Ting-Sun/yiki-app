/// 全域常數——API base URL 只在這裡改。
///
/// 開發環境對照（後端跑在電腦的 8000 port）：
/// - Android 真機（跟電腦同一個 Wi-Fi）→ 電腦區網 IP，例如：
///     http://192.168.10.100:8000（乙太網路）
///     http://192.168.10.101:8000（Wi-Fi）
///   （用 `ipconfig` 查最新 IP；後端要用 --host 0.0.0.0 啟動）
/// - Android 模擬器 → http://10.0.2.2:8000
/// - Chrome / Windows 桌面 → http://127.0.0.1:8000
class AppConstants {
  // Cloudflare 快速通道（使用者選擇；手機端不用裝任何東西）。
  // 注意：重啟「後端」不會換網址（通道自己會重連 8000）；
  // 只有「通道程式或電腦重開」才會換，屆時重跑
  //   cloudflared tunnel --url http://127.0.0.1:8000
  // 並回來改這行。備援：Tailscale 仍裝著，改回
  // 'http://100.74.148.113:8000'（手機 Tailscale 開著）即可。
  static const String apiBaseUrl =
      'https://symbol-launches-meals-tutorial.trycloudflare.com';

  static const String appName = '憶起';

  /// GPS 串流的最小移動距離（公尺），太密的點沒有意義。
  static const int gpsDistanceFilterM = 10;

  /// GPS 點累積幾個就批次上傳一次。
  static const int gpsBatchSize = 10;
}
