# NTE Fishing Bot Mac

<p align="center">
  <strong>給原生 macOS 版異環 / NTE 使用的非官方自動釣魚工具。</strong>
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="docs/TROUBLESHOOTING.md">疑難排解</a>
  ·
  <a href="CONTRIBUTING.md">貢獻指南</a>
  ·
  <a href="CHANGELOG.md">更新紀錄</a>
  ·
  <a href="docs/PUBLISHING.md">發布說明</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-111111">
  <img alt="Language" src="https://img.shields.io/badge/language-Swift-orange">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0--or--later-blue">
  <img alt="Status" src="https://img.shields.io/badge/status-fishing%20focused-green">
</p>

## 專案簡介

NTE Fishing Bot Mac 是一個小型 macOS 原生工具，目前只專注於一件事：
在原生 macOS 版 NTE / 異環中穩定循環釣魚。

它包含：

- 給一般使用者操作的 SwiftUI 小工具
- 給測試與校準使用的 Swift CLI
- 以畫面像素辨識開始釣魚、上鉤藍圈、釣魚跑條、結算畫面
- 只透過一般 macOS 鍵盤 / 滑鼠事件輸入

它不修改遊戲檔案、不修改記憶體、不攔截網路，也不注入遊戲程序。

## 目前範圍

這不是完整 MaaNTE 移植版。目前公開版本只做釣魚循環。

| 已支援 | 尚未包含 |
| --- | --- |
| 從可釣魚畫面自動按 `F` 開始 | 自動賣魚 |
| 等待右下角上鉤藍圈 | 自動買魚餌 |
| 自動按 `F` 進入跑條 | Maa 任務流程系統 |
| 用 `A` / `D` 控制跑條 | Windows 版本 |
| 關閉結算畫面 | PlayCover 支援 |
| 依設定數量或手動停止循環 | 其他遊戲任務 |

## 系統需求

| 項目 | 需求 |
| --- | --- |
| 作業系統 | macOS 14 或以上 |
| 遊戲版本 | 原生 macOS 版 NTE / 異環 |
| 處理器 | 預設提供 Apple Silicon build |
| 權限 | 螢幕錄製、輔助使用 |
| 建議視窗 | 視窗化或無邊框視窗 |
| 目前測試尺寸 | `0,33 1280x804` |

需要開啟的 macOS 權限：

- `系統設定 -> 隱私權與安全性 -> 螢幕錄製`
- `系統設定 -> 隱私權與安全性 -> 輔助使用`

開完權限後，請完全關閉並重新打開工具。

## 快速開始

### 方式一：下載 App

1. 到 GitHub Releases 下載 `MacFishingBotControl-macOS-arm64.zip`。
2. 解壓縮。
3. 打開 `MacFishingBotControl.app`。
4. 如果 macOS 要求權限，允許螢幕錄製與輔助使用。
5. 改完權限後，重新開啟 App。
6. 打開 NTE / 異環，切到穩定的視窗化大小。
7. 在工具內選擇遊戲視窗。
8. 按下「開始」。

### 方式二：自己建置

```bash
git clone https://github.com/Louis-369/NTEFishingBotMac.git
cd NTEFishingBotMac
script/build_app.sh
open dist/MacFishingBotControl.app
```

要產生 release zip：

```bash
script/package_release.sh
```

輸出會放在 `dist/`。

## 建議遊戲設定

請使用穩定的視窗化或無邊框視窗。現在測試最穩定的平衡尺寸是：

```text
x=0 y=33 width=1280 height=804
```

App 裡有固定尺寸按鈕，一般使用者不需要手動改 JSON。

建議條件：

- 遊戲視窗大小固定
- 右下角功能圖示可見
- 右下角 `F` 釣魚提示沒有被遮住
- 釣魚跑條出現在畫面上方中央
- 執行中不要改 macOS 顯示縮放

## 運作流程

自動釣魚是狀態機流程：

1. 偵測可開始釣魚的畫面。
2. 按 `F` 開始釣魚。
3. 等待右下角上鉤藍圈。
4. 再按 `F` 進入釣魚跑條。
5. 偵測綠色目標範圍與黃色游標。
6. 用 `A` / `D` 讓游標維持在綠色範圍內。
7. 偵測魚獲結算畫面。
8. 點擊結算提示區關閉。
9. 繼續下一輪，直到手動停止或達到設定數量。

預設控制模式是 `holdSwitch`，目前是針對原生 macOS 版與
`1280x804` 平衡尺寸調整。

## App 操作說明

| 控制項 | 用途 |
| --- | --- |
| 開始 | 開始自動釣魚循環 |
| 暫停 | 暫時停止流程 |
| 停止 | 停止自動化並放開按住的按鍵 |
| 視窗選擇 | 選擇 NTE / 異環視窗 |
| 固定尺寸 | 套用目前測試過的視窗尺寸 |
| 偵測面板 | 顯示 green / cursor / offset / 目前按鍵 |
| 日誌面板 | 顯示工具目前判斷與動作 |
| 進階設定 | 微調辨識與控制參數 |

App 緊急停止快捷鍵：

```text
Command + Option + .
```

CLI 緊急停止：

```text
Control + C
```

## CLI 用法

建置 CLI：

```bash
script/build_cli.sh
```

跑內建 self-test：

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot self-test
```

列出可見視窗：

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot list --all NTE
```

檢查截圖尺寸：

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot size --match NTE
```

只測偵測、不送出按鍵：

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot fish-probe cli/sample-fish-config.json
```

實際執行：

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot fish-run cli/sample-fish-config.json --live
```

## 設定說明

主要範例設定在 `cli/sample-fish-config.json`。

重要預設：

| 參數 | 預設值 | 說明 |
| --- | --- | --- |
| `dryRun` | `false` | App 預設會真的送出輸入 |
| `inputMode` | `global` | 使用一般 macOS 前景輸入 |
| `pauseWhenTargetNotFrontmost` | `true` | 遊戲不是前景時放開按鍵並等待 |
| `loopIntervalMs` | `16` | 釣魚主循環掃描間隔 |
| `controlMode` | `holdSwitch` | 按住方向，需要時切換 |
| `deadzonePx` | `15` | 忽略很小的 offset |
| `assistRequiresPrompt` | `true` | 看到提示時才輔助按鍵 |

一般使用者建議從 App 介面調整，不建議直接改 JSON。

## 專案結構

```text
app/      SwiftUI 控制工具源碼
cli/      Swift CLI 核心與範例設定
docs/     發布與疑難排解文件
script/   建置與打包腳本
dist/     本機建置輸出，不進 git
```

## 參考與鳴謝

本專案一開始參考了下列開源專案的自動化思路、任務呈現方式與文件組織：

- [MaaNTE](https://github.com/1bananachicken/MaaNTE)
- [MaaNTE 文檔站](https://docs.maante.org/)
- [MaaAssistantArknights](https://github.com/MaaAssistantArknights/MaaAssistantArknights)

這些專案是參考與靈感來源。本專案是獨立的 macOS-only 實作，不宣稱相容
Maa 任務框架，也不是 MaaNTE 官方版本。

## 隱私與安全

工具只讀取選定視窗的畫面像素，並送出一般 macOS 輸入事件。它不修改遊戲、
不注入程式、不讀取記憶體、不代理網路。

自動化可能違反遊戲服務條款，請自行評估風險。

## 授權

AGPL-3.0-or-later。詳見 `LICENSE`。

## 免責聲明

本專案為非官方工具，與 NTE / 異環開發商、發行商、MaaNTE、
MaaAssistantArknights 均無從屬、授權或背書關係。
