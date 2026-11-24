extension FixedWidthInteger {
    /// The integer's bytes, most significant first.
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian, Array.init)
    }
}
