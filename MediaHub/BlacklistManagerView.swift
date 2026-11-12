import SwiftUI
import Combine

struct BlacklistManagerView: View {
    static let size = CGSize(width: 464, height: 420)

    let document: BlacklistDocument
    let canRemove: Bool
    let status: String?
    let remove: (BlacklistEntry) -> Void

    private enum Tab: Hashable {
        case artists, songs
    }

    private final class Selection: ObservableObject {
        @Published var tab: Tab = .artists
        @Published var query = ""
    }

    @StateObject private var selection = Selection()
    private let accent = Color(nsColor: .systemPink)

    var body: some View {
        content
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(white: 0.09))
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabButton(.artists, key: "blacklist.artists")
            tabButton(.songs, key: "blacklist.songs")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("blacklist.filter"))
    }

    private func tabButton(_ tab: Tab, key: String) -> some View {
        let selected = selection.tab == tab
        return Button {
            selection.tab = tab
        } label: {
            Text(L(key))
                .font(.callout.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color(white: 0.70))
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(selected ? accent.opacity(0.23) : .clear, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var content: some View {
        let query = selection.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let artists = selection.tab == .songs ? [] : document.artists.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        let songs = selection.tab == .artists ? [] : document.songs.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.artistText.localizedStandardContains(query)
        }

        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(L("blacklist.search"), text: $selection.query)
                        .textFieldStyle(.plain)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))

                tabs
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider()
            if artists.isEmpty && songs.isEmpty {
                Text(L(query.isEmpty ? "blacklist.empty" : "blacklist.no_results"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !artists.isEmpty {
                            ForEach(artists, id: \.self) { artist in
                                row(artist.name, entry: .artist(artist))
                            }
                        }
                        if !songs.isEmpty {
                            ForEach(songs, id: \.self) { song in
                                row(song.title, subtitle: song.artistText, entry: .song(song))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }
                .defaultScrollAnchor(.top)
                .id(selection.tab)
            }
        }
    }

    private func row(_ title: String, subtitle: String? = nil, entry: BlacklistEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .help(subtitle.map { "\(title) — \($0)" } ?? title)

            Spacer(minLength: 0)
            Button {
                remove(entry)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(L("blacklist.remove_item"))
                .disabled(!canRemove)
                .help(L("blacklist.remove"))
        }
        .frame(minHeight: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}
