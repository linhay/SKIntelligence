//
//  File.swift
//
//
//  Created by linhey on 2024/4/1.
//

import Foundation
import JSONSchemaBuilder

/// https://fanyi-api.baidu.com/api/trans/product/apidoc
@Schemable()
public enum HumanLangeuage: String, Codable, Sendable {
    // 自动检测
    case auto = "auto"
    // 中文
    case zh = "zh"
    // 英语
    case en = "en"
    // 粤语
    case yue = "yue"
    // 文言文
    case wyw = "wyw"
    // 日语
    case jp = "jp"
    // 韩语
    case kor = "kor"
    // 法语
    case fra = "fra"
    // 西班牙语
    case spa = "spa"
    // 泰语
    case th = "th"
    // 阿拉伯语
    case ara = "ara"
    // 俄语
    case ru = "ru"
    // 葡萄牙语
    case pt = "pt"
    // 德语
    case de = "de"
    // 意大利语
    case it = "it"
    // 希腊语
    case el = "el"
    // 荷兰语
    case nl = "nl"
    // 波兰语
    case pl = "pl"
    // 保加利亚语
    case bul = "bul"
    // 爱沙尼亚语
    case est = "est"
    // 丹麦语
    case dan = "dan"
    // 芬兰语
    case fin = "fin"
    // 捷克语
    case cs = "cs"
    // 罗马尼亚语
    case rom = "rom"
    // 斯洛文尼亚语
    case slo = "slo"
    // 瑞典语
    case swe = "swe"
    // 匈牙利语
    case hu = "hu"
    // 繁体中文
    case cht = "cht"
    // 越南语
    case vie = "vie"
}
