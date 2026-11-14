import AppKit
import SwiftUI

struct DownloadsButton: View {
    let downloads: DownloadManager
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            ZStack {
                Image(systemName: "arrow.down.circle")
                    .imageScale(.large)
                if let progress = downloads.overallProgress {
                    Circle()
                        .trim(from: 0, to: max(progress, 0.03))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 22, height: 22)
                        .animation(.easeOut, value: progress)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Downloads")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DownloadsList(downloads: downloads)
        }
    }
}

private struct DownloadsList: View {
    let downloads: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Downloads").font(.headline)
                Spacer()
                Button("Clear") { downloads.clear() }
                    .disabled(downloads.items.allSatisfy { $0.state == .running })
            }
            .padding(12)
            Divider()
            if downloads.items.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle", description: Text("Files you download appear here."))
                    .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(downloads.items) { item in
                            DownloadRow(item: item)
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 360)
    }
}

private struct DownloadRow: View {
    let item: DownloadManager.Item

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.file.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.file.lastPathComponent).lineLimit(1).truncationMode(.middle)
                switch item.state {
                case .running:
                    ProgressView(value: item.progress ?? 0).controlSize(.small)
                case .finished:
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                case .failed(let reason):
                    Text(reason).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.state == .finished {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.file])
                } label: {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var detail: String {
        let size = (try? item.file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
        let date = item.date.formatted(date: .abbreviated, time: .shortened)
        guard let size else { return "\(date) · Moved or deleted" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) · \(date)"
    }
}
