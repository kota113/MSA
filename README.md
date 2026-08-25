# MacWSA PoC

Google公式Android EmulatorをVM基盤にし、AndroidアプリごとにmacOSの`NSWindow`を作るPoCです。フルAOSPのcheckout/buildは使いません。Android 16の公式AOSP userdebug emulator imageへ、platform署名したprivileged host agentだけを追加します。

```text
macOS / AppKit NSWindow
  H.264 video ◀──── adb TCP forward ────▶ input events
                                             │
Android Emulator (unmodified AOSP framework) │
  MacWsaAgent priv-app                       │
    VirtualDevice                            │
      ├─ VirtualDisplay → MediaCodec H.264 ──┘
      ├─ VirtualTouchscreen
      ├─ VirtualMouse
      └─ VirtualKeyboard
            └─ target Activity on that display
```

## 実装範囲

- Android 16 `VirtualDeviceManager`によるVirtualDevice/VirtualDisplay生成
- `ActivityOptions.setLaunchDisplayId()`による対象Activityの起動
- VirtualTouchscreen/VirtualMouse/VirtualKeyboardへのmacOS入力注入
- MediaCodecによるH.264転送とAppKit上での描画
- NSWindowの縦横比と表示サイズに合わせたVirtualDisplay・density・encoder・touchscreenの動的リサイズ
- 1接続 = 1 VirtualDevice = 1 NSWindow
- Companion Device app-streaming associationとroleの自動設定

音声、クリップボード、通知連携、IME変換、DRM保護映像は未実装です。

## ディレクトリ

- `android-agent/`: Gradleでビルドするplatform署名priv-app
- `macos-host/`: Swift Package/AppKitホスト（Xcodeプロジェクト不要）
- `scripts/`: SDK取得、AVD作成、priv-app導入、起動、検証
- `docs/protocol.md`: PoC通信プロトコル
- `aosp/`: 将来フルAOSP productを作る場合のfallback。通常は使用しません

## 容量

この手順では400GB級のAOSP source/build treeは不要です。主な消費はAndroid SDKのAPI 36 ARM64 image、AVD data、Gradle cacheで、PoC初期状態は数GB程度です。実測では40GB空きから開始し、セットアップ後も約36GB残りました。

## 必要環境

- Apple Silicon Mac
- Android SDK/Emulator（`~/Library/Android/sdk`を既定値として使用）
- Xcode Command Line Tools / Swift 6
- Java 17以降

## 初回セットアップ

```sh
cd ~/IdeaProjects/macwsa-poc
scripts/install-system-image.sh
scripts/fetch-android-prebuilts.sh
scripts/build-agent.sh
scripts/build-host.sh
```

`fetch-android-prebuilts.sh`が取得するものは、Android 16 system API stubとAOSP test platform keyだけです。AOSP source treeは取得しません。test keyはPoC専用で、配布製品には使えません。

## Emulator起動とagent導入

```sh
cd ~/IdeaProjects/macwsa-poc
scripts/start-emulator.sh
```

この起動スクリプトはApple Silicon MacのGPUを利用するため、Emulatorを`-gpu host`で起動します。映像ストリームは60fps設定のままです。

別ターミナルで、起動完了後に一度だけ実行します。

```sh
ANDROID_SERIAL=emulator-5556 scripts/install-priv-app.sh
```

このスクリプトはuserdebug imageを`adb root`/`adb remount`し、APKとprivapp permission allowlistを`/system/priv-app`へ追加して再起動します。その後、Companion Device association、app-streaming role、TCP forwardを設定します。

## 起動

Android SettingsをmacOSウィンドウとして開く例です。

```sh
ANDROID_SERIAL=emulator-5556 scripts/forward.sh
scripts/run-host.sh com.android.settings
```

インストール済みの別アプリはpackage名を置き換えます。2つ起動すれば、独立したVirtualDisplayとNSWindowが2つ作られます。

## AndroidアプリをmacOSの.appとして追加

Emulatorにインストール済みの任意のAndroidアプリから、FinderやSpotlightで起動できるmacOSアプリbundleを作れます。Android側の表示名をAPKから取得し、既定では`~/Applications`へ追加します。アイコンはAndroidの`PackageManager`でPNGへ描画してからmacOSの`.icns`へ変換するため、XML adaptive icon、vector drawable、通常の画像アイコンに対応します。

```sh
cd ~/IdeaProjects/macwsa-poc
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh com.android.vending
```

表示名を指定する場合は第2引数、保存先を変える場合は第3引数を使います。

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh com.example.app "My Android App" "$HOME/Desktop"
```

作成済みのbundleを新しいホストやアイコンで更新する場合は`--replace`を付けます。

```sh
ANDROID_SERIAL=emulator-5558 scripts/create-macos-app.sh --replace com.android.vending
```

生成された`.app`にはAndroid package名だけが設定として埋め込まれます。APKやGoogle Playのコードは同梱せず、共通のAndroid Emulatorとagentへ接続します。開く前にEmulatorとTCP forwardを起動してください。

```sh
scripts/start-gms-emulator.sh
ANDROID_SERIAL=emulator-5558 scripts/forward.sh
open "$HOME/Applications/Google Play Store.app"
```

## Google Play実験用AVD（rootAVD）

Google Play StoreとGMSを使う実験用構成は、通常のAOSP AVDとは別の`macwsa-gms-api36`として用意します。SDKのGoogle Play imageをAPFSのコピーオンライトで分離してからrootAVD/Magiskで専用ramdiskだけを変更するため、既存のPixel AVDと元のsystem imageには影響しません。

初回だけ次を実行します。

```sh
cd ~/IdeaProjects/macwsa-poc
scripts/setup-gms-avd.sh
GMS_EMULATOR_WINDOW=1 scripts/start-gms-emulator.sh
```

別ターミナルでrootAVDを実行します。完了時にEmulatorは終了します。

```sh
ANDROID_SERIAL=emulator-5558 scripts/root-gms-emulator.sh
```

再度`GMS_EMULATOR_WINDOW=1 scripts/start-gms-emulator.sh`で起動し、Magiskを開いてAdditional setupを承認します。自動再起動後、MagiskのSuperuser画面で`[SharedUID] Shell`を有効にしてからagent moduleを導入します。

```sh
ANDROID_SERIAL=emulator-5558 scripts/install-gms-agent.sh
```

通常起動ではウィンドウ不要です。

```sh
scripts/start-gms-emulator.sh
ANDROID_SERIAL=emulator-5558 scripts/forward.sh
scripts/run-host.sh com.android.settings
scripts/run-host.sh com.android.vending
```

これはローカル実験専用です。Google Play image、GMS、Magisk、rootAVD、agent APKを成果物へ同梱・再配布しないでください。root化されたEmulatorではPlay Integrity、DRM、Walletなどが動作しない場合があります。

## 検証

```sh
ANDROID_SERIAL=emulator-5556 scripts/smoke-test.sh com.android.settings

adb -s emulator-5556 shell dumpsys virtualdevice
adb -s emulator-5556 shell dumpsys display
adb -s emulator-5556 shell dumpsys input
adb -s emulator-5556 shell dumpsys activity activities
adb -s emulator-5556 logcat -s MacWsaAgent
```

成功時はVirtual Device、`MacWSA Display`、Touch/Mouse/Keyboard、および対象Activityのdisplay IDが確認できます。NSWindowを閉じると接続に属するencoder、virtual input、display、deviceを閉じます。

## セキュリティ上の境界

PoCプロトコルには認証がありません。agentのTCPポートをLANへ公開せず、`adb forward`経由のlocalhost接続だけで使用してください。製品化では独自署名鍵、認証済みIPC、更新機構、権限の最小化が必要です。
