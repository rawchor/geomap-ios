import Foundation

@MainActor
final class MyStatusViewModel: ObservableObject {
    static let customTextLimit = 30

    @Published private(set) var presets: [StatusPresetOptionResponse] = []
    @Published private(set) var currentStatus: StatusResponse?
    @Published var searchText = "" {
        didSet {
            if searchText.count > Self.customTextLimit {
                searchText = String(searchText.prefix(Self.customTextLimit))
            }
        }
    }
    @Published var selectedExpiry: StatusExpiry = .untilChanged
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    var filteredPresets: [StatusPresetOptionResponse] {
        guard !searchText.isEmpty else { return presets }
        return presets.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
    }

    /// Typed text that exactly matches a preset's label resolves to that
    /// preset rather than free text, per the "type to search — resolves to
    /// either a preset match or free text" spec.
    var matchingPreset: StatusPresetOptionResponse? {
        presets.first { $0.label.caseInsensitiveCompare(searchText) == .orderedSame }
    }

    var canSaveAsCustomText: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && matchingPreset == nil
    }

    func loadInitialData() async {
        isLoading = true
        errorMessage = nil
        do {
            async let presetsResult = apiClient.statusPresets()
            async let statusResult = apiClient.myStatus()
            presets = try await presetsResult
            currentStatus = try await statusResult
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isLoading = false
    }

    func selectPreset(_ preset: StatusPresetOptionResponse) async {
        await save(presetOptionId: preset.id, customText: nil)
    }

    func saveCustomText() async {
        guard canSaveAsCustomText else { return }
        await save(presetOptionId: nil, customText: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearStatus() async {
        selectedExpiry = .untilChanged
        await save(presetOptionId: nil, customText: nil)
    }

    private func save(presetOptionId: UUID?, customText: String?) async {
        isSaving = true
        errorMessage = nil
        do {
            currentStatus = try await apiClient.updateStatus(
                StatusUpdateRequest(
                    presetOptionId: presetOptionId,
                    customText: customText,
                    durationMinutes: selectedExpiry.minutes
                )
            )
            // Not currentStatus?.displayText: that's decorated with the
            // preset emoji for read-only display, and feeding it back into
            // the search field would filter every preset out of
            // filteredPresets (none contain the emoji), hiding the list.
            // Clearing instead shows the full picker again, ready for the
            // next choice.
            searchText = ""
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isSaving = false
    }
}
