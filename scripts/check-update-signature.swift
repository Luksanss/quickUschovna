// Checks a Sparkle EdDSA signature against the public key in the app's own Info.plist, the way
// Sparkle checks it on the user's Mac. A release whose private key doesn't match the app's public
// key then fails here, instead of failing every update after it ships.
//
//   xcrun swift scripts/check-update-signature.swift <file> <signature> <Info.plist>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: check-update-signature.swift <file> <signature> <Info.plist>\n".utf8))
    exit(64)
}

let info = NSDictionary(contentsOfFile: arguments[3])
guard let keyString = info?["SUPublicEDKey"] as? String,
      let keyData = Data(base64Encoded: keyString),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("\(arguments[3]) has no valid SUPublicEDKey")
}
guard let signature = Data(base64Encoded: arguments[2]) else {
    fail("the signature isn't base64")
}
guard let file = try? Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe) else {
    fail("can't read \(arguments[1])")
}
guard publicKey.isValidSignature(signature, for: file) else {
    fail("the signature doesn't match the app's SUPublicEDKey, so Sparkle would reject this update")
}
print("The signature matches the app's SUPublicEDKey.")
