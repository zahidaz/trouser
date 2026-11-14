import SwiftUI

struct StringListEditor: View {
    let title: String
    let detail: String
    let prompt: String
    @Binding var values: [String]
    let normalize: (String) -> String?
    @State private var draft = ""

    var body: some View {
        Section {
            ForEach(values, id: \.self) { value in
                HStack {
                    Text(value).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        values.removeAll { $0 == value }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }
            HStack {
                TextField(title, text: $draft, prompt: Text(prompt))
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(candidate == nil)
            }
        } header: {
            Text(title)
        } footer: {
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var candidate: String? {
        normalize(draft).flatMap { values.contains($0) ? nil : $0 }
    }

    private func add() {
        guard let candidate else { return }
        values.append(candidate)
        draft = ""
    }
}
