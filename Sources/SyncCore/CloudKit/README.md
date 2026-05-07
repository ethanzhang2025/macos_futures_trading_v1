# CloudKitSyncBackend · Mac 切机接入指南（WP-60）

## 状态
- ✅ Linux: 整文件 `#if canImport(CloudKit)` 跳过 · 编译过
- ⏳ Mac: 切机后按下方步骤配置 + 联调

## 切机配置步骤

### 1. Container 创建
1. 登录 [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list/cloudContainer)
2. 新建 iCloud Container ID：`iCloud.com.<yourorg>.FuturesTerminal`
3. App 的 App ID 启用 iCloud capability，关联此 container

### 2. Entitlements 配置
在 MainApp 目录下加 `MainApp.entitlements`：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.<yourorg>.FuturesTerminal</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

Xcode：Target → Signing & Capabilities → + Capability → iCloud → 勾选 CloudKit + Container。

### 3. Schema Deploy
首次启动时，CloudKit Dashboard：
1. https://icloud.developer.apple.com/dashboard/
2. 选 container
3. Development env → Schema 自动从 client 字段推断（首次 push 时建）
4. 测完后 Deploy to Production

### 4. Code 接入
```swift
import CloudKit
import SyncCore

// 在 App 启动早期（如 MainApp.init）
let container = CKContainer(identifier: "iCloud.com.<yourorg>.FuturesTerminal")
let backend = CloudKitSyncBackend(container: container, scope: .private)
let engine = SyncEngine(backend: backend)

// 同步 Watchlist
let book: WatchlistBook = ... // 从 store 加载
let records = try book.groups.map { try $0.toSyncRecord() }
let result = try await engine.sync(localRecords: records, recordType: Watchlist.syncRecordType)
let merged = try result.merged.map { try Watchlist.decode(from: $0) }
let visible = merged.filter { $0.deletedAt == nil }
let newBook = WatchlistBook(groups: visible)
// ... 持久化 newBook + 写 ConflictLog
```

### 5. 验收
- ✅ 两台 Mac 同步 watchlist 分组（添加/重命名/拖拽）
- ✅ 删除（softDeleteGroup）传播到对端
- ✅ 离线 + 重连合并不丢
- ✅ 冲突场景（双方同时改）记录到 ConflictLog
- ⏳ iPad 同步（WP-61 接入）

## CKRecord 字段约定

| CKField           | 类型       | 来源                |
|-------------------|------------|---------------------|
| `lastModified`    | Date       | `SyncRecord.lastModified` |
| `version`         | Int64      | `SyncRecord.version`      |
| `deletedAt`       | Date?      | `SyncRecord.deletedAt`    |
| `payload`         | Data       | Adapter JSON 编码         |

`recordType` 直用 `SyncRecord.recordType`（"watchlist" / "workspace_template" / "settings"）
`recordName` = `id.uuidString`

## 敏感数据隔离（D4 G1 方案 A）

仅以下 recordType 走 CloudKit：
- `watchlist`（自选 · 非敏感）
- `workspace_template`（工作区 · 非敏感）
- `settings`（UI 偏好 · 非敏感）

以下不走 CloudKit · Stage B 阿里云自建：
- `journal`（交易日志 · PII）
- `alert`（预警条件 · 含交易意图）
- 未来：trade（成交记录 · 强 PII）

## 错误映射

| CKError              | SyncBackendError       |
|----------------------|------------------------|
| networkUnavailable   | networkUnavailable     |
| notAuthenticated     | authenticationRequired |
| quotaExceeded        | quotaExceeded          |
| requestRateLimited   | rateLimited            |
| unknownItem          | recordNotFound         |
| invalidArguments     | schemaMismatch         |
| 其他                 | unknown                |

## 已知 TODO（后续 batch / WP）

- [ ] CKSubscription · 推送通知变更（避免轮询）
- [ ] Schema 版本演进策略（业务字段加减时）
- [ ] Asset 字段（payload > 1MB 时降级）
- [ ] 物理 GC tombstone（30 天后清理）
- [ ] WatchlistBook 整体 sync（vs 分组级 sync）
