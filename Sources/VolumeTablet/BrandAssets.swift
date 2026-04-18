import AppKit

enum BrandAssets {
    static func markImage() -> NSImage? {
        loadImage(named: "stylusdeck-mark")
    }

    private static func loadImage(named name: String) -> NSImage? {
        if let bundledURL = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Brand") {
            return NSImage(contentsOf: bundledURL)
        }

        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/brand/\(name).png")
        return NSImage(contentsOf: fallbackURL)
    }
}
