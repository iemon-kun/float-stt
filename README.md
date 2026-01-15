# FloatSTT

FloatSTTは、マイク音声をリアルタイムで文字起こしし、必要なときに浮かぶウィンドウからテキストを貼り付けできるmacOSアプリです。SwiftUIとLocalSpeechAPI（AVFoundation＋VAD＋ローカルのSpeechフレームワーク）を組み合わせ、シンプルなUIとホットキーで操作できます。

## 主な特徴
- 常に手前に表示できる最小化されたパネルと、透明なキーボードキャプチャビュー。
- カスタマイズ可能なホットキー（`FloatingPanelController`と`HotKeyManager`により管理）。
- 音声検知（VAD）とローカルのSpeechフレームワークでリアルタイムにテキストを抽出し、`TextInserter`でカーソル位置に注入する仕組み。
- アセットは`nano-banana/`配下にAI生成されたアイコンで、いえもんくんの錬処（@iemon_kun）が選定・加工した素材です。

## セットアップと実行
1. Xcode 15以上またはSwift 5.9対応の環境を用意。
2. ターミナルでこのリポジトリに移動し、依存関係はSwift標準なので特別な準備は不要。
3. `swift build`でビルド、`swift run FloatSTT`または`dist/FloatSTT.app`を起動して動作を確認。
4. アプリを配布する際は、`nano-banana/`配下のアイコンとREADMEで利用条件を明記。

## ドキュメント
- 詳しい英語版READMEは[README.en.md](README.en.md)をご覧ください。
- ライセンスと権利情報は[LICENSE](LICENSE)にまとめています。

## 開発メモ
- Notion: 各モジュールの責務は`FloatingOverlayModel.swift`や`FloatingPanelController.swift`、`SettingsWindowController.swift`などで分割。
- `build.sh`や`dist/`は手動生成の出力フォルダなので`.gitignore`に追加済みです。

## クレジット
- アイコン・素材: AI生成素材を、いえもんくんの錬処（@iemon_kun）が選定・加工したもの。
- ライセンス: MIT（詳しくは[LICENSE](LICENSE)）。
