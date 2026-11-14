import SwiftUI

struct PatternListSection<Extra: View>: View {
    let title: String
    let footer: String
    let placeholder: String
    let items: [String]
    let add: (String) -> Bool
    let remove: (String) -> Void
    let extra: () -> Extra
    @State private var draft = ""
    @State private var isInvalid = false

    init(
        title: String,
        footer: String,
        placeholder: String,
        items: [String],
        add: @escaping (String) -> Bool,
        remove: @escaping (String) -> Void,
        @ViewBuilder extra: @escaping () -> Extra
    ) {
        self.title = title
        self.footer = footer
        self.placeholder = placeholder
        self.items = items
        self.add = add
        self.remove = remove
        self.extra = extra
    }

    var body: some View {
        Section {
            ForEach(items, id: \.self) { item in
                HStack {
                    Text(item).font(.body.monospaced())
                    Spacer()
                    Button {
                        remove(item)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Remove")
                }
            }
            HStack {
                TextField("New entry", text: $draft, prompt: Text(placeholder))
                    .labelsHidden()
                    .onSubmit(submit)
                Button("Add", action: submit)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isInvalid {
                Text("“\(draft)” is not a valid pattern.").font(.caption).foregroundStyle(.red)
            }
            extra()
        } header: {
            Text(title)
        } footer: {
            Text(footer).foregroundStyle(.secondary)
        }
    }

    private func submit() {
        isInvalid = !add(draft)
        if !isInvalid {
            draft = ""
        }
    }
}

extension PatternListSection where Extra == EmptyView {
    init(
        title: String,
        footer: String,
        placeholder: String,
        items: [String],
        add: @escaping (String) -> Bool,
        remove: @escaping (String) -> Void
    ) {
        self.init(title: title, footer: footer, placeholder: placeholder, items: items, add: add, remove: remove) {
            EmptyView()
        }
    }
}
