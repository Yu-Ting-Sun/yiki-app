# 憶起 App（yiki_app）

家庭旅遊回憶系統的手機 App:外出用 GPS + 照片記錄旅程、AI 生成遊記、
沿途收藏景點,回家推播到 M55M1 智慧相框重現回憶。

## 功能總覽(全部完成 ✅)

| 功能 | 說明 |
|---|---|
| GPS 記錄 | 開始/結束行程、即時地圖跟隨、距離/時間統計、每 10 點批次上傳(失敗自動重試) |
| 附近景點 | 記錄中查目前位置周邊的美食/景點(Overpass 真實 POI + AI 介紹兩段式載入),點擊開 Google 地圖,⭐ 收藏進旅程 |
| 照片 | 記錄中拍照/選相簿上傳;旅程結束後也能「補照片」(多選、讀 EXIF 座標與拍攝時間落在軌跡正確位置) |
| 旅程清單 | 卡片式(封面縮圖、日期、距離)、下拉重新整理、左滑刪除 |
| 旅程詳情 | 軌跡地圖(Polyline + 起訖 + 照片標記)、照片橫列(點開大圖)、收藏的景點、遊記 |
| AI 遊記 | 用真實資料生成:行程統計 + 停留偵測比對「真的去過」的地點 + vision 看照片內容;可全文編輯 |
| 相框同步 | 6 位配對碼配對;M55M1 **整批同步所有旅程**到 SD 卡(每趟一個資料夾:遊記文字/LCD 文字圖/TTS 語音/板子尺寸照片),版本號比對只載有變動的 |

## 啟動後端

後端在 `../m55m1_dual_model_poc/backend/`(跟 M55M1 相框共用同一個 FastAPI):

```powershell
cd ..\m55m1_dual_model_poc\backend
$env:OPENAI_API_KEY = "sk-..."   # LLM 用(遊記/景點介紹);沒 key 可改 $env:LLM_MOCK = "1"
C:\Users\antia\anaconda3\envs\m55m1_face\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

- **一定要用 `m55m1_face` 這個 python 完整路徑**(PATH 上的 python/pip 是別的環境)。
- `--host 0.0.0.0` 必加,手機/板子才連得到。
- Swagger UI: <http://127.0.0.1:8000/docs>
- 資料庫 `backend/yiki.db`(SQLite),刪掉即重置;照片在 `backend/photo_store/`。
- TTS 需要 ffmpeg 在 PATH(已裝);遊記 vision 需要模型支援看圖(gemini-3-flash OK)。
- **防火牆**要放行 8000 port(Public 網路預設全擋):
  ```powershell
  # 系統管理員 PowerShell
  netsh advfirewall firewall add rule name="Yiki FastAPI 8000" dir=in action=allow protocol=TCP localport=8000
  ```

## 跑 App

```powershell
cd yiki_app
flutter run          # 手機接 USB、開 USB 偵錯
```

### API base URL(重要)

只在 [lib/core/constants.dart](lib/core/constants.dart) 一個地方改:

| 執行環境 | apiBaseUrl |
|---|---|
| **Android 真機**(與電腦同 Wi-Fi) | `http://<電腦區網IP>:8000`(`ipconfig` 查 Wi-Fi 的 IPv4;**別用 vEthernet/WSL 的 172.x**) |
| Android 模擬器 | `http://10.0.2.2:8000` |
| Edge/Chrome(`-d edge`) | `http://127.0.0.1:8000`(後端已開 CORS) |

改完 IP 要**熱重啟**(flutter run 視窗按大寫 `R`)。

### 相框配對與同步(demo)

**每塊板子有自己的身分**:板子開機用 ESP 的 MAC 向 `POST /frames/register`
註冊,拿到專屬 frame_id + 6 位配對碼並**顯示在 LCD 右欄**(`Pair: 483920`),
App 輸入那組碼配對。旅程會歸屬到「記錄當下已配對的相框」(沒配對=所有相框
都同步得到)。兩塊板子同一個 Wi-Fi 也各自獨立。

**同步是按需的(門鈴模式)**:App 相框頁按「立即同步」→ 後端立旗 →
板子每 10 秒一個 ~100 bytes 的 `GET /frames/{id}/pending` 輪詢,看到旗子
才真正下載(SD 全空的首次開機會自動同步一次)。

後端另外種了一台 demo 相框,配對碼 **123456**(沒有實體板子也能測 App 流程)。

M55M1 同步流程——SD 卡結構**對齊板端 Slideshow 相簿架構**(`0:\pictures\<相簿>\`,
一趟旅程一本相簿,最多 15 本、超過取最新):

```powershell
# 1. 拉同步清單(有內容的旅程 + 檔案 URL + 參加者 + 版本號)
curl.exe -s http://127.0.0.1:8000/frames/1/sync

# 2. 韌體對每趟旅程:VERSION.TXT 跟 manifest 的 version 一樣 → 整趟跳過
#    不一樣 → 逐檔下載進 pictures\T{id:04d}\:
curl.exe -s -o LABEL.JSON http://127.0.0.1:8000/trips/<id>/label.json  # {"users": [...]} 人臉過濾用
curl.exe -s -o STORY.TXT  http://127.0.0.1:8000/trips/<id>/story.txt   # 遊記文字
curl.exe -s -o STORY.TIM  http://127.0.0.1:8000/trips/<id>/story.tim   # LCD TIM4 文字圖
curl.exe -s -o STORY.WAV  http://127.0.0.1:8000/trips/<id>/story.wav   # 16kHz TTS 語音
curl.exe -s -o P0001.JPG  "http://127.0.0.1:8000/photos/<pid>/board"   # 480px baseline JPEG
#    最後把 version 寫進 VERSION.TXT
```

- 照片可帶 `?w=320` 調整成板子 LCD 寬度(64-1024);STORY.* 和 VERSION.TXT
  不是 .jpg,板端相簿掃描會自動略過。
- **參加者**在旅程詳情頁編輯(最多 8 位、名字需與相框人臉註冊 label 一致),
  就是相簿 `label.json` 的內容——人臉辨識認出誰,就播誰參加過的旅程。

## 已知限制

- **GPS 只支援前景記錄**(螢幕要亮著)。Backlog:前景服務背景續跑 +
  隔天詢問「要儲存昨天的行程嗎」(需 local-first 儲存、常駐通知、
  Samsung 省電白名單)。
- 景點資料來自 **Overpass 公用實例**(免費),尖峰時偶爾整批過載,
  稍等重試即可(後端已輪替 5 個鏡像 + 快取)。
- 遊記的「真的去過」判定取**最近的 POI**,廣場型大景點(如赤崁樓)
  可能被門口小店搶走;生成後可手動編輯。
- 相框同步的 TTS/文字圖/縮圖以內容 hash 快取在 `backend/trip_media/` 與
  `photo_store/board_*.jpg`,遊記改了會自動重做;第一次同步每趟 TTS 要幾秒。
- 對後端走 HTTP 明文(開發用),AndroidManifest 已開 `usesCleartextTraffic`。
- 出門在外(不在電腦區網)連不到後端——demo 時用手機熱點讓電腦跟著上網。

## 開發環境(這台電腦已裝好)

- Flutter 3.44.5 stable:`C:\src\flutter`(使用者 PATH;JDK 路徑已寫進 `flutter config --jdk-dir`)
- JDK Temurin 17(`JAVA_HOME`)、Android SDK 36(`ANDROID_HOME`)
- 環境變數是使用者層級,舊終端機看不到 → 重開 VS Code 或手動 `$env:Path` 補
