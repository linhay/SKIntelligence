//
//  SKIVectorObject.swift
//  SKIntelligence
//
//  Created by linhey on 10/17/25.
//

import Foundation

public struct SKIVectorObject<ID: Hashable>: Identifiable {
    public let id: ID
    public let vector: [Float]
    public init(id: ID, vector: [Float]) {
        self.id = id
        self.vector = vector
    }
}

public extension SKISimilarityIndex {
    /// 添加新的向量与对应的标识符。
    func append(object: SKIVectorObject<ID>) {
        self.append(vector: object.vector, id: object.id)
    }
    
    /// 插入或更新指定标识符对应的向量。
    func upsert(object: SKIVectorObject<ID>) {
        self.upsert(vector: object.vector, id: object.id)
    }
    
    /// 更新已存在的向量，若标识符不存在返回 false。
    @discardableResult
    func update(object: SKIVectorObject<ID>) -> Bool {
        return self.update(vector: object.vector, id: object.id)
    }
    
    /// 删除指定标识符对应的向量，若标识符不存在返回 false。
    @discardableResult
    func remove(object: SKIVectorObject<ID>) -> Bool {
        return self.remove(object.id)
    }
    
}
