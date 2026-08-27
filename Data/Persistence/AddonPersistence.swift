import Foundation

actor AddonPersistence {
    private let keychain: KeychainStore
    private let accountPrefix = "addon-profile."

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load(profileID: String) -> AddonPersistenceState {
        guard let data = keychain.readData(account: account(for: profileID)) else {
            return AddonPersistenceState()
        }
        return (try? JSONDecoder().decode(AddonPersistenceState.self, from: data))
            ?? AddonPersistenceState()
    }

    func save(_ state: AddonPersistenceState, profileID: String) throws {
        let data = try JSONEncoder().encode(state)
        try keychain.writeData(data, account: account(for: profileID))
    }

    private func account(for profileID: String) -> String {
        accountPrefix + Data(profileID.utf8).base64EncodedString()
    }
}
