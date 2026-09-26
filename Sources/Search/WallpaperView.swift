import SwiftUI
import UniformTypeIdentifiers

struct WallpaperView: View {
    @ObservedObject private var wallpaper = Wallpaper.shared

    var body: some View {
        GeometryReader { area in
            if wallpaper.enabled, let image = wallpaper.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: wallpaper.fit ? .fit : .fill)
                    .frame(width: area.size.width, height: area.size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: wallpaper.enabled) { await wallpaper.load() }
    }
}

struct WallpaperSettings: View {
    let announce: (String) -> Void
    @ObservedObject private var wallpaper = Wallpaper.shared
    @State private var choosing = false

    var body: some View {
        Card {
            Line("New tab image", "A picture behind the address field") {
                Switch(on: $wallpaper.enabled)
            }
            if wallpaper.enabled || wallpaper.hasImage {
                Rule()
                Line("Image", wallpaper.busy ? "Preparing image…" : "A copy is kept in Search") {
                    HStack(spacing: 6) {
                        Pill(wallpaper.hasImage ? "Change…" : "Choose…") { choose() }
                        if wallpaper.hasImage {
                            Pill("Remove") {
                                Task {
                                    await wallpaper.remove()
                                    if let error = wallpaper.error { announce(error) }
                                }
                            }
                        }
                    }
                }
            }
            if wallpaper.enabled, wallpaper.hasImage {
                Rule()
                Line("Layout", wallpaper.fit ? "Show the whole picture" : "Fill the page without stretching") {
                    Segmented(options: [(false, "Fill"), (true, "Fit")], selection: $wallpaper.fit)
                }
            }
            if let error = wallpaper.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(14)
            }
        }
        .disabled(wallpaper.busy || choosing)
        .onChange(of: wallpaper.enabled) { _, on in
            if on, !wallpaper.hasImage { choose() }
        }
    }

    private func choose() {
        guard !choosing else { return }
        choosing = true
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .heif]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use image"
        panel.begin { response in
            choosing = false
            guard response == .OK, let url = panel.url else {
                if !wallpaper.hasImage { wallpaper.enabled = false }
                return
            }
            Task {
                await wallpaper.use(url)
                if let error = wallpaper.error { announce(error) }
            }
        }
    }
}
