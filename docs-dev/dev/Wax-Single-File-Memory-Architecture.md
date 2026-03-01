# Wax 如何实现「持久、可搜索、私有、单文件」内存

## 1. 范围与结论

本报告基于 `references/Wax` 源码，聚焦四个问题：

1. 持久：写入后如何落盘并可恢复。
2. 可搜索：如何做文本/向量/混合检索。
3. 私有：为什么默认是本地私有。
4. 单文件：为什么整个库状态可以放进一个 `.wax` 文件。

结论：
- Wax 的核心状态确实围绕单个 `.wax` 文件构建，包含 header/WAL/payload/TOC/footer。
- 持久性依赖 WAL + 双页头 + 校验和 + 打开时修复/回放。
- 可搜索依赖 FTS5（文本）+ USearch/Metal（向量）+ RRF 混合融合。
- “私有”是架构默认（本地、无强制服务端）；但并非默认“加密存储”。

---

## 2. 单文件实现（Single File）

### 2.1 文件布局

Wax 文档明确给出 `.wax` 的顺序布局：
- Header A（4 KiB）
- Header B（4 KiB）
- WAL Ring（默认 256 MiB）
- Frame Payloads（变长）
- TOC（变长）
- Footer（64 bytes）

参考：
- `references/Wax/Sources/WaxCore/WaxCore.docc/Articles/FileFormat.md`

### 2.2 创建流程即写入完整单文件骨架

`Wax.create(at:)` 会在同一个文件中完成：
- 创建文件并上锁
- 写初始 TOC
- 写 Footer
- 写 Header A/B
- `fsync`

参考：
- `references/Wax/Sources/WaxCore/Wax.swift`

这说明不是“多文件元数据库 + 外部索引”的松耦合模型，而是单文件容纳核心状态。

---

## 3. 持久实现（Durability）

### 3.1 WAL 先行，提交后推进 checkpoint

WAL 设计为固定大小 ring buffer，mutation 先写 WAL，再 commit 推进 checkpoint。  
记录包含 sequence、payload length、flags、payload checksum，支持 padding/sentinel。

参考：
- `references/Wax/Sources/WaxCore/WaxCore.docc/Articles/WALAndCrashRecovery.md`
- `references/Wax/Sources/WaxCore/WAL/WALRingWriter.swift`
- `references/Wax/Sources/WaxCore/WAL/WALRingReader.swift`

### 3.2 崩溃恢复

打开时流程（`Wax.open`）包含：
- 读取并选择有效 Header A/B（按 generation 与 checksum）
- 扫描/定位最新有效 footer
- 读取 TOC 并校验范围
- 扫描 WAL 未提交 mutation 并重建内存状态
- 必要时修复尾部脏数据（truncate 到安全边界）

参考：
- `references/Wax/Sources/WaxCore/Wax.swift`
- `references/Wax/Sources/WaxCore/FileFormat/FooterScanner.swift`

### 3.3 多层校验

关键层都使用 SHA-256 校验：
- header checksum
- WAL record payload checksum
- TOC checksum
- footer 中 TOC hash 校验

参考：
- `references/Wax/Sources/WaxCore/WaxCore.docc/Articles/FileFormat.md`
- `references/Wax/Sources/WaxCore/WaxCore.docc/Articles/WALAndCrashRecovery.md`

---

## 4. 可搜索实现（Searchability）

### 4.1 文本检索：FTS5 + BM25

`FTS5SearchEngine` 基于 GRDB/SQLite FTS5：
- 写入时 upsert/remove 到 `frames_fts`
- 查询时使用 `MATCH` + `bm25(...)`
- 返回 snippet 与得分

参考：
- `references/Wax/Sources/WaxTextSearch/FTS5SearchEngine.swift`

### 4.2 向量检索：USearch/Metal

`USearchVectorEngine` 负责 ANN 索引：
- `add/remove/search`
- 索引可序列化后写回 Wax（`stageForCommit`）
- 打开时可从 committed vec segment 反序列化，并叠加 pending embedding mutations

参考：
- `references/Wax/Sources/WaxVectorSearch/USearchVectorEngine.swift`
- `references/Wax/Sources/WaxVectorSearch/MetalVectorEngine.swift`
- `references/Wax/Sources/WaxVectorSearch/VectorSerializer.swift`

### 4.3 混合检索：RRF 融合

`UnifiedSearch` 将 text/vector/timeline/structured lanes 融合，核心算法为 weighted RRF。  
可按 query 类型与 mode 调整权重和候选集。

参考：
- `references/Wax/Sources/Wax/UnifiedSearch/UnifiedSearch.swift`
- `references/Wax/Sources/Wax/UnifiedSearch/HybridSearch.swift`

---

## 5. 私有实现（Privacy by default）

### 5.1 本地执行与本地存储

`MemoryOrchestrator` 默认对本地 `Wax` 文件执行 open/create 与检索，不依赖远端数据库。  
嵌入模型可走本地 CoreML MiniLM（启用 trait 时），MCP server 也可用本地 stdio 运行。

参考：
- `references/Wax/Sources/Wax/Orchestrator/MemoryOrchestrator.swift`
- `references/Wax/Sources/WaxVectorSearchMiniLM/MiniLMEmbedder.swift`
- `references/Wax/Sources/WaxMCPServer/main.swift`

### 5.2 并发与进程级访问控制

文件级 `flock`（shared/exclusive）+ actor 隔离，减少并发写损坏风险。  
这属于一致性/隔离基础，不等同于加密。

参考：
- `references/Wax/Sources/WaxCore/IO/FileLock.swift`
- `references/Wax/Sources/WaxCore/Wax.swift`

### 5.3 边界说明

“私有”在 Wax 语境里主要是“默认不出设备、不依赖云服务”。  
源码层面未体现“默认透明磁盘加密（application-level encryption at rest）”能力；若业务要求强加密，仍需结合系统数据保护或应用层二次加密策略。

---

## 6. 对我们接入的含义

1. 若我们只需要可落地的本地记忆层，Wax 的单文件 + WAL 恢复机制足够成熟。  
2. 若我们需要“合规级强隐私”，要补加密策略，不应只用“本地存储”作为合规结论。  
3. 若要做检索质量，Wax 已有 text/vector/hybrid 基础，适合作为 `SKIMemory` 的持久后端候选。

---

## 7. Wax 如何调用 `MiniLM-L6-v2.mlmodelc`

### 7.1 资源打包

`WaxVectorSearchMiniLM` target 在包清单里显式拷贝模型资源：
- `.copy("Resources/all-MiniLM-L6-v2.mlmodelc")`
- `.process("Resources/bert_tokenizer_vocab.txt")`

参考：
- `references/Wax/Package.swift`

### 7.2 入口初始化

常见入口是：
- `MemoryOrchestrator.openMiniLM(...)`

内部流程：
1. `MiniLMEmbedder()` 初始化模型包装器  
2. `embedder.prewarm()` 先做一次预热推理  
3. 注入 `MemoryOrchestrator(at:config:embedder:)`

参考：
- `references/Wax/Sources/Wax/Adapters/MemoryOrchestrator+MiniLM.swift`

### 7.3 模型加载

`MiniLMEmbeddings` 加载模型时会从 SwiftPM 模块资源里找：
- `Bundle.module.url(forResource: "all-MiniLM-L6-v2", withExtension: "mlmodelc")`

拿到 URL 后用 `MLModel(contentsOf:configuration:)` 加载，再包装成 `all_MiniLM_L6_v2`。

参考：
- `references/Wax/Sources/WaxVectorSearchMiniLM/CoreML/MiniLMEmbeddings.swift`
- `references/Wax/Sources/WaxVectorSearchMiniLM/CoreML/all-MiniLM-L6-v2.swift`

### 7.4 推理调用链

单条文本：
1. `MiniLMEmbedder.embed(_ text:)`
2. `MiniLMEmbeddings.encode(sentence:)`
3. `BertTokenizer` 生成 `input_ids` 与 `attention_mask`
4. `model.prediction(...)` 执行 CoreML 推理
5. 从输出 `var_554` 解码成 384 维向量

批量文本：
- `MiniLMEmbedder.embed(batch:)` -> `MiniLMEmbeddings.encode(batch:reuseBuffers:)`  
- 使用批量路径减少开销、提升吞吐。

参考：
- `references/Wax/Sources/WaxVectorSearchMiniLM/MiniLMEmbedder.swift`
- `references/Wax/Sources/WaxVectorSearchMiniLM/CoreML/MiniLMEmbeddings.swift`
- `references/Wax/Sources/WaxVectorSearchMiniLM/CoreML/BertTokenizer.swift`

### 7.5 在检索系统中的使用

`MemoryOrchestrator` 在 ingest/query 阶段调用 embedder 生成向量，并写入向量索引路径（用于 vector/hybrid 搜索）。

参考：
- `references/Wax/Sources/Wax/Orchestrator/MemoryOrchestrator.swift`
