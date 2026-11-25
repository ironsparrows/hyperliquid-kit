import Foundation
import HyperliquidKitCore

/// An EIP-712 message with one flat struct type, such as the `Agent` an action's signature covers.
///
/// Hyperliquid's domains always have version `"1"` and the zero address as verifying contract.
struct TypedData {
    let domainName: String
    let chainID: UInt64
    let primaryType: String
    let fields: [Field]

    struct Field {
        let name: String
        let value: Value
    }

    enum Value {
        case string(String)
        case bytes32([UInt8])
        case address(Hyperliquid.Address)
        case uint64(UInt64)
    }

    /// The hash to sign: `keccak256(0x19 0x01 ‖ domain separator ‖ struct hash)`.
    var digest: [UInt8] {
        Keccak256.hash([0x19, 0x01] + domainSeparator + structHash)
    }

    var signingRequest: Hyperliquid.SigningRequest {
        Hyperliquid.SigningRequest(digest: Data(digest), typedData: json.json)
    }

    private static let zeroAddress: Hyperliquid.Address = "0x0000000000000000000000000000000000000000"

    private var domainSeparator: [UInt8] {
        let type = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        return Keccak256.hash(
            Keccak256.hash(Array(type.utf8))
                + Value.string(domainName).encoded
                + Value.string("1").encoded
                + Value.uint64(chainID).encoded
                + Value.address(Self.zeroAddress).encoded
        )
    }

    private var structHash: [UInt8] {
        let type = primaryType + "(" + fields.map { "\($0.value.typeName) \($0.name)" }.joined(separator: ",") + ")"
        return Keccak256.hash(Keccak256.hash(Array(type.utf8)) + fields.flatMap(\.value.encoded))
    }

    /// The message as `eth_signTypedData_v4` takes it: the domain, then the types (the primary type
    /// before `EIP712Domain`), the primary type and the message. This is the layout of an L1 action;
    /// actions signed by the account's own wallet lay it out differently, and only their ``digest`` is
    /// used.
    private var json: ActionValue {
        let domainTypes: ActionValue = [
            ["name": "name", "type": "string"],
            ["name": "version", "type": "string"],
            ["name": "chainId", "type": "uint256"],
            ["name": "verifyingContract", "type": "address"],
        ]
        let messageTypes = ActionValue.array(fields.map { ["name": .string($0.name), "type": .string($0.value.typeName)] })
        let message = ActionValue.map(fields.map { .init(key: $0.name, value: $0.value.json) })
        return [
            "domain": [
                "chainId": .unsigned(chainID),
                "name": .string(domainName),
                "verifyingContract": .string(Self.zeroAddress.description),
                "version": "1",
            ],
            "types": .map([.init(key: primaryType, value: messageTypes), .init(key: "EIP712Domain", value: domainTypes)]),
            "primaryType": .string(primaryType),
            "message": message,
        ]
    }
}

extension TypedData.Value {
    fileprivate var typeName: String {
        switch self {
        case .string: "string"
        case .bytes32: "bytes32"
        case .address: "address"
        case .uint64: "uint64"
        }
    }

    /// The 32-byte word EIP-712 hashes for the value. `uint64` and `uint256` encode alike.
    fileprivate var encoded: [UInt8] {
        switch self {
        case .string(let text):
            return Keccak256.hash(Array(text.utf8))
        case .bytes32(let bytes):
            precondition(bytes.count == 32, "A bytes32 value has \(bytes.count) bytes")
            return bytes
        case .address(let address):
            return [UInt8](repeating: 0, count: 12) + address.bytes
        case .uint64(let value):
            return [UInt8](repeating: 0, count: 24) + value.bigEndianBytes
        }
    }

    fileprivate var json: ActionValue {
        switch self {
        case .string(let text): .string(text)
        case .bytes32(let bytes): .string(hexadecimal(bytes))
        case .address(let address): .string(address.description)
        case .uint64(let value): .unsigned(value)
        }
    }
}
