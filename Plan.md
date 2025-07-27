# Swift類似コード検出ツール 実装計画書

## 1. プロジェクト概要

### 目標
Swiftのリファクタリング支援ツールとして、APTED（All-Pairs Tree Edit Distance）アルゴリズムを使ってコードの類似度を計算し、類似コードを検出する。

### 技術スタック
- Swift
- swift-syntax (AST解析)
- 独自APTED実装
- ArgumentParser (CLI)

## 2. アーキテクチャ

### コンポーネント

| コンポーネント | 責務 | 技術 |
|---|---|---|
| AST パーサー | SwiftコードからASTを生成 | swift-syntax |
| Tree構造変換器 | SwiftSyntax ASTを汎用的な木構造データに変換 | Swift |
| APTED実装 | 木編集距離を計算するアルゴリズム | Swift (独自実装) |
| 類似度計算エンジン | スコアリングとしきい値判定 | Swift |
| CLIツール | コマンドライン界面 | ArgumentParser |

### データフロー

1. Swift ソースファイル
2. swift-syntax による AST 生成
3. 汎用木構造への正規化
4. APTED による編集距離算出
5. 類似度スコアリング
6. レポート生成

## 3. 実装順序

### Phase 1: 基盤構築

#### タスク
1. **swift-syntaxの統合**
   - Package.swiftの依存関係設定
   - 基本的なASTパース機能の実装
   - ソースファイル読み込み・解析パイプライン

2. **汎用Tree構造の設計**
   ```swift
   protocol TreeNode {
       var label: String { get }
       var children: [TreeNode] { get }
   }
   
   struct SimpleTreeNode: TreeNode {
       let label: String
       let children: [TreeNode]
   }
   ```

#### 成果物
- 基本的なAST解析機能
- Tree構造の定義
- ファイル読み込み機能

### Phase 2: APTED実装

#### タスク
1. **基本的なAPTEDアルゴリズム**
   - 木編集距離の計算
   - 挿入・削除・置換操作のコスト定義
   - 動的プログラミングによる最適化

2. **最適化済みAPTED**
   - 既存のPython/Java実装を参考に最適化
   - メモリ効率とパフォーマンスの改善
   - 大規模木構造への対応

#### 成果物
- APTED アルゴリズムの完全実装
- パフォーマンステスト
- メモリ効率の最適化

### Phase 3: AST変換器

#### タスク
1. **SwiftSyntax → TreeNode変換**
   - 主要なSyntax要素のマッピング
   - ノードの正規化とフィルタリング
   - 変数名などの抽象化オプション

2. **設定可能な変換オプション**
   - コメント・空白の無視
   - 変数名の抽象化レベル調整
   - 特定構文要素のフィルタリング

#### 成果物
- AST → Tree変換器
- 設定可能な正規化オプション
- フィルタリング機能

### Phase 4: 類似度計算とスコアリング

#### Step 1: 高度な類似度メトリクス ✅
- **複数指標の組み合わせ**
  - 構造的類似度（ツリー形状ベース）
  - ラベル類似度（共通ラベル率）
  - 深度類似度（ツリー深度比較）
- **重み付き統合計算**
  - 設定可能な重み（デフォルト: 0.6/0.3/0.1）
  - 重みの自動正規化
- **詳細結果レポート**
  - 各メトリクスの個別スコア
  - 総合類似度スコア

#### Step 2: 並列処理対応
- **複数ファイル並列比較**
  ```swift
  // 複数ファイル間の並列類似度計算
  ParallelSimilarityCalculator.compareFiles(paths, threshold: 0.8)
  ```
- **バッチ処理最適化**
  - DispatchQueue活用による並列処理
  - メモリ効率的なタスク分割
  - 進捗報告機能
- **結果集約とレポート**
  - 類似ペアの効率的収集
  - スコア順ソート
  - 重複除去

#### Step 3: キャッシュシステム
- **AST解析結果キャッシュ**
  ```swift
  // ファイルハッシュベースのAST cache
  ASTCache.shared.getCachedAST(for: filePath, contentHash: hash)
  ```
- **類似度計算結果キャッシュ**
  - ペア単位の計算結果保存
  - 設定変更時の無効化
  - LRU-based cache管理
- **永続化対応**
  - ディスクベースキャッシュ
  - プロジェクト単位のキャッシュ管理

#### Step 4: 統合テストとベンチマーク
- **パフォーマンステスト**
  - 大量ファイル処理時間測定
  - メモリ使用量監視
  - キャッシュ効果確認
- **実用性検証**
  - 実際のSwiftプロジェクトでの動作確認
  - 類似コード検出精度評価

#### 成果物
- AdvancedSimilarityMetrics ✅
- ParallelSimilarityCalculator
- ASTCache & SimilarityCache
- パフォーマンスベンチマーク

### Phase 5: CLIツールとレポート

#### タスク
1. **コマンドライン界面**
   ```bash
   swift-similarity compare file1.swift file2.swift
   swift-similarity scan project/ --threshold=0.8
   swift-similarity report --format=json --output=results.json
   ```

2. **レポート機能**
   - JSON/テキスト形式での出力
   - 類似コードペアの詳細表示
   - 統計情報とサマリー

#### 成果物
- 完全なCLIツール
- 多様な出力フォーマット

## 4. 技術的課題と解決方針

### 4.1 SwiftSyntax AST の複雑性

**課題**: SwiftSyntaxのASTは非常に詳細で、ノイズが多い

**解決策**:
- セマンティック的に重要なノードのみを抽出
- トークンレベルの詳細は抽象化
- 設定可能なフィルタリングオプション

### 4.2 APTED の計算量

**課題**: 大きな木構造に対するAPTEDは指数的時間

**解決策**:
- 事前に木のサイズ制限
- 分割統治法による近似アルゴリズム
- 並列処理による高速化

### 4.3 スケーラビリティ

**課題**: 大規模プロジェクトでのパフォーマンス

**解決策**:
- 並列処理の活用
- インデックス化とキャッシュ
- 段階的な比較戦略

## 5. テスト要件

### 単体テスト
- APTED アルゴリズムの正確性
- AST変換の正当性
- エッジケースの処理

### 統合テスト
- 実際のSwiftコードでの動作確認
- パフォーマンスベンチマーク
- 既知の類似コードペアでの精度検証

### 実用性テスト
- 大規模プロジェクトでの動作確認
- リファクタリング支援としての有効性検証

---

## 4. 実装状況

### 完了したタスク
- ✅ **Phase 1: 基盤構築** - `a358c0b`
- ✅ **Phase 2: APTED実装** - `54ca759`  
- ✅ **プロジェクト構造整理** - `0ede7d3`

---

この計画に従って、段階的にSwift類似コード検出ツールを開発します。 