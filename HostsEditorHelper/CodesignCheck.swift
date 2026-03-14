import Foundation
import Security

private let defaultSecFlags = SecCSFlags(rawValue: 0)

enum CodesignCheckError: Error {
    case message(String)
}

struct CodesignCheck {
    static func codeSigningMatches(pid: pid_t) throws -> Bool {
        try codeSigningCertificatesForSelf() == codeSigningCertificates(forPID: pid)
    }

    private static func codeSigningCertificatesForSelf() throws -> [SecCertificate] {
        guard let staticCode = try secStaticCodeForSelf() else { return [] }
        return try codeSigningCertificates(forStaticCode: staticCode)
    }

    private static func codeSigningCertificates(forPID pid: pid_t) throws -> [SecCertificate] {
        guard let staticCode = try secStaticCode(forPID: pid) else { return [] }
        return try codeSigningCertificates(forStaticCode: staticCode)
    }

    private static func executeSecurityCall(_ body: () -> OSStatus) throws {
        let status = body()
        guard status == errSecSuccess else {
            throw CodesignCheckError.message(String(describing: SecCopyErrorMessageString(status, nil)))
        }
    }

    private static func secStaticCodeForSelf() throws -> SecStaticCode? {
        var code: SecCode?
        try executeSecurityCall {
            SecCodeCopySelf(defaultSecFlags, &code)
        }
        guard let code else {
            throw CodesignCheckError.message("Missing self SecCode")
        }
        return try secStaticCode(forSecCode: code)
    }

    private static func secStaticCode(forPID pid: pid_t) throws -> SecStaticCode? {
        var code: SecCode?
        try executeSecurityCall {
            SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code)
        }
        guard let code else {
            throw CodesignCheckError.message("Missing guest SecCode")
        }
        return try secStaticCode(forSecCode: code)
    }

    private static func secStaticCode(forSecCode code: SecCode) throws -> SecStaticCode? {
        var staticCode: SecStaticCode?
        try executeSecurityCall {
            SecCodeCopyStaticCode(code, [], &staticCode)
        }
        guard let staticCode else {
            throw CodesignCheckError.message("Missing SecStaticCode")
        }
        return staticCode
    }

    private static func codeSigningCertificates(forStaticCode staticCode: SecStaticCode) throws -> [SecCertificate] {
        try executeSecurityCall {
            SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSDoNotValidateResources | kSecCSCheckNestedCode), nil)
        }

        var info: CFDictionary?
        try executeSecurityCall {
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        }

        guard
            let signingInfo = info as? [String: Any],
            let certificates = signingInfo[kSecCodeInfoCertificates as String] as? [SecCertificate]
        else {
            return []
        }

        return certificates
    }
}
