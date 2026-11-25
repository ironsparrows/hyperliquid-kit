import Foundation
import Gzip

/// The bytes of a compressed push: base64 text of a raw DEFLATE stream (RFC 1951), with no zlib or
/// gzip header, or `nil` when the text doesn't decode.
func inflated(base64 text: String) -> Data? {
    guard let compressed = Data(base64Encoded: text) else { return nil }
    // A negative window size makes zlib read raw DEFLATE.
    return try? compressed.gunzipped(wBits: -15)
}
