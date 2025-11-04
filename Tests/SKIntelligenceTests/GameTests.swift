import Testing
import Foundation
import JSONSchemaBuilder
import SKIntelligence
import SKITools

class SKINPCCreateTool: SKITool {
    
    @Schemable
    struct Arguments {
        @SchemaOptions(.description("NPC与主角的关系"))
        let relationship: String
    }
    
    @Schemable
    struct ToolOutput: Codable {
        
        let name: String?
        let description: String?
        @SchemaOptions(.description("可能的错误信息"))
        let error: String?
        let done: Bool
        
        init(name: String? = nil, description: String? = nil, error: String? = nil, done: Bool = false) {
            self.name = name
            self.description = description
            self.error = error
            self.done = done
        }
    }
    
    var name: String = "createNPC"
    var description: String = "创建一个NPC角色, 返回他的名字、年龄和职业。"
    var isEnabled: Bool = true
    
    var list: [ToolOutput] = [
        .init(name: "小刚", description: "小刚是一个强壮的战士，年龄25岁，职业是战士。他擅长近战战斗和防御，是主角的护卫。")
    ]
    
    func call(_ arguments: Arguments) async throws -> ToolOutput {
        guard let npc = list.first else {
            isEnabled = false
            return ToolOutput(error: "没有可用的NPC。", done: true)
        }
        list.removeFirst()
        return npc
    }
    
}

class SKIQuestFetchTool: SKITool {
    
    @Schemable
    struct Arguments {
        @SchemaOptions(.description("任务的名称或编号"))
        let questID: String
    }
    
    @Schemable
    struct ToolOutput: Codable {
        let title: String?
        let summary: String?
        @SchemaOptions(.description("任务是否完成"))
        let completed: Bool
        @SchemaOptions(.description("可能的错误信息"))
        let error: String?
        
        init(title: String? = nil, summary: String? = nil, completed: Bool = false, error: String? = nil) {
            self.title = title
            self.summary = summary
            self.completed = completed
            self.error = error
        }
    }
    
    var name: String = "fetchQuestResult"
    var description: String = "获取指定任务的结果，包含标题、摘要和完成状态。"
    var isEnabled: Bool = true
    
    var quests: [String: ToolOutput] = [
        "quest001": .init(title: "寻找失落的宝石", summary: "主角找到了失落的宝石并交还给村民。", completed: true),
        "quest002": .init(title: "击败山贼", summary: "任务尚未完成，山贼仍在活动。", completed: false)
    ]
    
    func call(_ arguments: Arguments) async throws -> ToolOutput {
        guard let result = quests[arguments.questID] else {
            return ToolOutput(error: "未找到对应的任务结果。")
        }
        return result
    }
}



@Test func game() async throws {
    let client = OpenAIClient()
        .model(.gemini_2_5_flash)
        .token(Keys.google)
        .url(.gemini)
    let transcript = SKITranscript()
    let session = SKILanguageModelSession(client: client,
                                          transcript: transcript,
                                          tools: [
                                            SKIToolQueryCalendar(),
                                            SKIToolLocalDate(),
                                            SKINPCCreateTool(),
                                            SKIQuestFetchTool()
                                          ])
    let response = try await session.respond(to: """
        你来到了异世界，今天是 {当前日期}。
        你的小队刚刚招募了一位伙伴：{NPC姓名}。
        他是 {NPC描述}
        
        你的当前任务是：寻找失落的宝石
        状态：{完成状态}
        简要情况：{任务摘要}
        
        请继续前进，做出下一个决策！
        """)
    print(response)
}


@Test func calendar() async throws {
    let client = OpenAIClient()
        .model(.gemini_2_5_flash)
        .token(Keys.google)
        .url(.gemini)
    let transcript = SKITranscript()
    let session = SKILanguageModelSession(client: client,
                                          transcript: transcript,
                                          tools: [
                                            SKIToolQueryCalendar(),
                                            SKIToolLocalDate()
                                          ])
    let response = try await session.respond(to: """
        我的日历上最近有什么安排？请帮我查询一下。
        """)
    print(response)
}

@Test func translate() async throws {
    let tool = SKIToolBaiduTranslate(authentication: Keys.baiduAuthentication)
    let response = try await tool.call(.init(q: "测试", from: .auto, to: .en))
    print(response)
}
