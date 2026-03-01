//
//  GameTests.swift
//  SKIntelligence
//
//  Tests for game-like scenarios using LLM with tool calling.
//

import Foundation
import JSONSchemaBuilder
import SKITools
import SKIClients
import SKIntelligence
import Testing

#if canImport(EventKit)

    // MARK: - Game Tools Namespace

    /// Game-specific tools for RPG-like interactions
    enum GameTools {

        // MARK: - NPC Tool

        /// Tool for creating and managing NPC characters
        final class NPCManager: SKITool {

            @Schemable
            struct Arguments: Sendable {
                @SchemaOptions(.description("NPC与主角的关系类型，如：伙伴、敌人、商人、村民"))
                let relationship: String

                @SchemaOptions(.description("可选的NPC职业偏好"))
                let preferredClass: String?
            }

            @Schemable
            struct ToolOutput: Codable, Sendable {
                let id: String
                let name: String
                let description: String
                let relationship: String
                /// 等级
                let level: Int?
                /// 生命值
                let health: Int?
                /// 攻击力
                let attack: Int?
                /// 防御力
                let defense: Int?
            }

            let name: String = "createNPC"
            let description: String = """
                创建一个游戏NPC角色。
                返回NPC的基本信息，包括名字、描述、关系和属性。
                """

            private let npcDatabase: [ToolOutput] = [
                ToolOutput(
                    id: "npc_001",
                    name: "小刚",
                    description: "一位年轻的战士，身材魁梧，擅长近战。曾是村里的铁匠学徒，后来决定追随冒险者的道路。",
                    relationship: "伙伴",
                    level: 5, health: 120, attack: 25, defense: 15
                ),
                ToolOutput(
                    id: "npc_002",
                    name: "李婆婆",
                    description: "村口的老草药师，精通各种草药的配方，经常帮助路过的冒险者。",
                    relationship: "村民",
                    level: nil, health: nil, attack: nil, defense: nil
                ),
                ToolOutput(
                    id: "npc_003",
                    name: "黑风",
                    description: "神秘的流浪剑客，来历不明，似乎在寻找什么重要的东西。",
                    relationship: "伙伴",
                    level: 12, health: 200, attack: 45, defense: 20
                ),
            ]

            func call(_ arguments: Arguments) async throws -> ToolOutput {
                // Filter by relationship if specified
                let candidates = npcDatabase.filter { npc in
                    npc.relationship.contains(arguments.relationship)
                        || arguments.relationship.contains(npc.relationship)
                }

                guard let npc = candidates.first ?? npcDatabase.first else {
                    throw SKIToolError.executionFailed(reason: "没有符合条件的NPC")
                }

                return npc
            }
        }

        // MARK: - Quest Tool

        /// Tool for managing game quests and objectives
        final class QuestManager: SKITool {

            @Schemable
            struct Arguments: Sendable {
                @SchemaOptions(.description("任务的唯一标识符"))
                let questID: String

                @SchemaOptions(.description("操作类型：query(查询), accept(接受), complete(完成)"))
                let action: String?
            }

            @Schemable
            struct ToolOutput: Codable, Sendable {
                let questID: String
                let title: String
                let description: String
                let objectives: [String]
                /// 任务状态：可接取、进行中、已完成、已失败
                let status: String
                /// 金币奖励
                let rewardGold: Int?
                /// 经验奖励
                let rewardExp: Int?
                /// 物品奖励（逗号分隔）
                let rewardItems: String?
            }

            let name: String = "manageQuest"
            let description: String = """
                管理游戏任务系统。
                支持查询任务详情、接受任务和完成任务。
                """

            private let quests: [String: ToolOutput] = [
                "quest_001": ToolOutput(
                    questID: "quest_001",
                    title: "失落的宝石",
                    description: "村长的祖传宝石在一次山贼袭击中被夺走，请找回这颗珍贵的宝石。",
                    objectives: ["找到山贼营地", "击败山贼头目", "取回宝石", "返回村长家"],
                    status: "进行中",
                    rewardGold: 500, rewardExp: 1200, rewardItems: "铁剑, 治疗药水x3"
                ),
                "quest_002": ToolOutput(
                    questID: "quest_002",
                    title: "草药采集",
                    description: "李婆婆需要一些山上的珍稀草药来配制解毒剂。",
                    objectives: ["采集月光草x5", "采集火焰花x3", "返回给李婆婆"],
                    status: "可接取",
                    rewardGold: 150, rewardExp: 300, rewardItems: "解毒剂x2"
                ),
                "quest_003": ToolOutput(
                    questID: "quest_003",
                    title: "神秘剑客的委托",
                    description: "黑风似乎在寻找一件古老的神器，他希望你能帮助他。",
                    objectives: ["对话了解详情", "前往古遗迹", "寻找神器线索"],
                    status: "可接取",
                    rewardGold: 1000, rewardExp: 2500, rewardItems: nil
                ),
            ]

            func call(_ arguments: Arguments) async throws -> ToolOutput {
                guard let quest = quests[arguments.questID] else {
                    throw SKIToolError.invalidArguments("未找到任务: \(arguments.questID)")
                }
                return quest
            }
        }

        // MARK: - Inventory Tool

        /// Tool for managing player inventory
        final class InventoryManager: SKITool {

            @Schemable
            struct Arguments: Sendable {
                @SchemaOptions(.description("操作类型：list(列出物品), use(使用物品), equip(装备物品)"))
                let action: String

                @SchemaOptions(.description("物品名称（使用或装备时需要）"))
                let itemName: String?
            }

            @Schemable
            struct ToolOutput: Codable, Sendable {
                let success: Bool
                let message: String
                /// 物品列表JSON字符串
                let inventoryJSON: String?
            }

            let name: String = "manageInventory"
            let description: String = "管理玩家背包和物品"

            private let inventoryList = """
                [
                  {"name": "铁剑", "type": "武器", "quantity": 1, "description": "一把普通的铁剑，锋利耐用"},
                  {"name": "皮甲", "type": "防具", "quantity": 1, "description": "轻便的皮革护甲"},
                  {"name": "治疗药水", "type": "消耗品", "quantity": 5, "description": "恢复50点生命值"},
                  {"name": "火把", "type": "道具", "quantity": 3, "description": "照亮黑暗区域"},
                  {"name": "金币", "type": "货币", "quantity": 350, "description": "通用货币"}
                ]
                """

            func call(_ arguments: Arguments) async throws -> ToolOutput {
                switch arguments.action.lowercased() {
                case "list":
                    return ToolOutput(
                        success: true,
                        message: "当前背包物品",
                        inventoryJSON: inventoryList
                    )
                case "use":
                    guard let itemName = arguments.itemName else {
                        throw SKIToolError.invalidArguments("使用物品需要指定物品名称")
                    }
                    return ToolOutput(
                        success: true,
                        message: "成功使用了 \(itemName)",
                        inventoryJSON: nil
                    )
                case "equip":
                    guard let itemName = arguments.itemName else {
                        throw SKIToolError.invalidArguments("装备物品需要指定物品名称")
                    }
                    return ToolOutput(
                        success: true,
                        message: "已装备 \(itemName)",
                        inventoryJSON: nil
                    )
                default:
                    throw SKIToolError.invalidArguments("未知操作: \(arguments.action)")
                }
            }
        }
    }

    // MARK: - Test Suite

    @Suite("Game Scenario Tests")
    struct GameTests {

        private var liveProviderTestsEnabled: Bool {
            ProcessInfo.processInfo.environment["RUN_LIVE_PROVIDER_TESTS"] == "1"
        }

        // MARK: - Shared Configuration

        /// Default client configuration for game tests
        private var client: OpenAIClient {
            OpenAIClient().profiles([
                .init(
                    url: URL(string: OpenAIClient.EmbeddedURL.openrouter.rawValue)!,
                    token: Keys.openrouter,
                    model: "xiaomi/mimo-v2-flash:free"
                )
            ])
        }

        private var transcript: SKITranscript {
            get async {
                let transcript = SKITranscript()
                await transcript.setObserveNewEntry(.print())
                return transcript
            }
        }

        // MARK: - RPG Scenario Tests

        /// Test: Complete RPG scenario with NPC and quest interactions
        @Test("RPG scenario with NPC recruitment and quest progression")
        func rpgScenario() async throws {
            guard liveProviderTestsEnabled else { return }
            let session = await SKILanguageModelSession(
                client: client,
                transcript: transcript,
                tools: [
                    SKIToolLocalDate(),
                    GameTools.NPCManager(),
                    GameTools.QuestManager(),
                    GameTools.InventoryManager(),
                ]
            )

            let response = try await session.respond(
                to: """
                    # 异世界冒险

                    今天是 {请查询当前日期}。

                    你刚刚来到这个异世界的小村庄，需要开始你的冒险之旅。

                    请完成以下任务：
                    1. 招募一位伙伴加入你的队伍
                    2. 查看当前进行中的任务 quest_001
                    3. 检查你的背包物品

                    然后给出一个简短的冒险日志总结。
                    """)

            print("=== RPG Scenario Response ===")
            print(response)

            #expect(!response.isEmpty)
        }

        /// Test: Quest management workflow
        @Test("Quest management with multiple queries")
        func questManagement() async throws {
            guard liveProviderTestsEnabled else { return }

            let session = await SKILanguageModelSession(
                client: client,
                transcript: transcript,
                tools: [GameTools.QuestManager()]
            )

            let response = try await session.respond(
                to: """
                    请帮我查询以下任务的详情：
                    1. quest_001 - 我想知道这个任务的目标和奖励
                    2. quest_002 - 这个任务需要做什么

                    请整理成一个任务清单供我参考。
                    """)

            print("=== Quest Management Response ===")
            print(response)

            #expect(!response.isEmpty)
        }

        // MARK: - Tool Integration Tests

        /// Test: Calendar tool for scheduling
        @Test("Calendar tool for game events")
        func calendarIntegration() async throws {
            guard liveProviderTestsEnabled else { return }
            let session = SKILanguageModelSession(
                client: client,
                transcript: SKITranscript(),
                tools: [
                    SKIToolQueryCalendar(),
                    SKIToolLocalDate(),
                ]
            )

            let response = try await session.respond(
                to: """
                    请查看我最近的日程安排，看看有没有可以进行冒险的时间。
                    """)

            print("=== Calendar Response ===")
            print(response)

            #expect(!response.isEmpty)
        }

        /// Test: Translation tool
        @Test("Translation tool standalone")
        func translationTool() async throws {
            guard liveProviderTestsEnabled else { return }
            let tool = SKIToolBaiduTranslate(authentication: Keys.baiduAuthentication)
            let result = try await tool.call(.init(q: "勇敢的冒险者", from: .zh, to: .en))

            print("=== Translation Result ===")
            print("Original: 勇敢的冒险者")
            print("Translated: \(result.trans_result.first?.dst ?? "N/A")")

            #expect(!result.trans_result.isEmpty)
        }

        // MARK: - Multi-turn Conversation Tests

        /// Test: Multi-turn conversation maintaining context
        @Test("Multi-turn conversation with context")
        func multiTurnConversation() async throws {
            guard liveProviderTestsEnabled else { return }
            let transcript = SKITranscript()
            let session = SKILanguageModelSession(
                client: client,
                transcript: transcript,
                tools: [
                    GameTools.NPCManager(),
                    GameTools.InventoryManager(),
                ]
            )

            // First turn: Recruit NPC
            let response1 = try await session.respond(to: "请招募一位伙伴加入队伍")
            print("=== Turn 1 ===")
            print(response1)

            // Second turn: Check inventory
            let response2 = try await session.respond(to: "现在请查看我们的装备和物品")
            print("=== Turn 2 ===")
            print(response2)

            // Verify context is maintained
            #expect(!response1.isEmpty)
            #expect(!response2.isEmpty)

            // Check transcript has multiple entries
            let entries = await transcript.entries
            #expect(entries.count >= 4)  // At least 2 prompts + 2 responses
        }
    }

#endif
