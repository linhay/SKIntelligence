// MARK: - L2Normalizer
public struct L2Normalizer<T: BinaryFloatingPoint> {
    public var sqrootSumSquared: T?

    public init() {}

    public init(sqrootSumSquared: T) {
        self.sqrootSumSquared = sqrootSumSquared
    }

    /// 对向量进行 L2 归一化
    public mutating func normalized(_ vector: [T]) -> [T] {
        let sumSquares = vector.reduce(0) { $0 + $1 * $1 }
        let sqrootSumSquared = sumSquares.squareRoot()
        self.sqrootSumSquared = sqrootSumSquared

        guard sqrootSumSquared != 0 else { return vector } // 防止除以 0
        return vector.map { $0 / sqrootSumSquared }
    }

    /// 对单个值进行归一化（依赖上一次 normalized 的结果）
    public func normalize(_ value: T) -> T {
        guard let sqrootSumSquared = self.sqrootSumSquared, sqrootSumSquared != 0 else {
            return value
        }
        return value / sqrootSumSquared
    }

    /// 对单个值进行反归一化
    public func denormalize(_ value: T) -> T {
        guard let sqrootSumSquared = self.sqrootSumSquared else {
            return value
        }
        return value * sqrootSumSquared
    }
}
