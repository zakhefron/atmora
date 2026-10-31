import Foundation

/// The six ambiences Atmora ships with. Raw values double as stable
/// persistence keys and audio directory names.
public enum EnvironmentID: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case rainyCabin = "rainy-cabin"
    case train
    case sakuraNight = "sakura-night"
    case cloudLibrary = "cloud-library"
    case sunsetDrive = "sunset-drive"
    case seasideRecords = "seaside-records"

    public var id: String { rawValue }
}

/// One independently controllable audio channel inside an ambience.
public struct SoundLayer: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let symbolName: String
    /// Path relative to the bundled `Audio` directory.
    public let fileName: String
    public let defaultLevel: Double

    public init(
        id: String,
        name: String,
        detail: String,
        symbolName: String,
        fileName: String,
        defaultLevel: Double
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.symbolName = symbolName
        self.fileName = fileName
        self.defaultLevel = defaultLevel
    }
}

public struct SoundEnvironment: Identifiable, Hashable, Sendable {
    public let id: EnvironmentID
    public let name: String
    public let tagline: String
    public let description: String
    public let layers: [SoundLayer]

    public init(
        id: EnvironmentID,
        name: String,
        tagline: String,
        description: String,
        layers: [SoundLayer]
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.description = description
        self.layers = layers
    }

    public var defaultLevels: [String: Double] {
        Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.defaultLevel) })
    }

    public func layer(id: String) -> SoundLayer? {
        layers.first { $0.id == id }
    }
}

public struct EnvironmentCatalog: Sendable {
    public let environments: [SoundEnvironment]

    public init(environments: [SoundEnvironment]) {
        self.environments = environments
    }

    public subscript(id: EnvironmentID) -> SoundEnvironment? {
        environments.first { $0.id == id }
    }

    public func environment(for id: EnvironmentID) -> SoundEnvironment? {
        self[id]
    }

    public var allLayerFileNames: [String] {
        environments.flatMap { $0.layers.map(\.fileName) }
    }

    /// Structural checks used by tests and the asset validator. Empty means the
    /// catalogue is internally consistent.
    public var integrityIssues: [String] {
        var issues: [String] = []
        let ids = environments.map(\.id)
        if Set(ids).count != ids.count {
            issues.append("Ambience identifiers are not unique.")
        }
        if environments.count != EnvironmentID.allCases.count {
            issues.append("Catalogue does not contain every declared ambience.")
        }

        let files = allLayerFileNames
        if Set(files).count != files.count {
            issues.append("Two sound layers share an audio file.")
        }

        for environment in environments {
            if environment.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("\(environment.id.rawValue): missing name.")
            }
            if environment.layers.isEmpty {
                issues.append("\(environment.id.rawValue): no sound layers.")
            }
            if environment.description.isEmpty {
                issues.append("\(environment.id.rawValue): missing description.")
            }

            let layerIDs = environment.layers.map(\.id)
            if Set(layerIDs).count != layerIDs.count {
                issues.append("\(environment.id.rawValue): duplicate layer identifiers.")
            }

            for layer in environment.layers {
                if !(0...1).contains(layer.defaultLevel) {
                    issues.append("\(environment.id.rawValue)/\(layer.id): default level out of range.")
                }
                if layer.fileName.isEmpty || layer.fileName.contains("..") {
                    issues.append("\(environment.id.rawValue)/\(layer.id): invalid file name.")
                }
                if layer.name.isEmpty {
                    issues.append("\(environment.id.rawValue)/\(layer.id): missing label.")
                }
            }
        }
        return issues
    }

    public static let standard: EnvironmentCatalog = {
        let catalog = EnvironmentCatalog(environments: [
            SoundEnvironment(
                id: .rainyCabin,
                name: "Rainy Cabin",
                tagline: "Rain, fire, and distant thunder",
                description: "Rain drifts across the glass, the fire settles, and the evening belongs to you.",
                layers: [
                    SoundLayer(
                        id: "rain",
                        name: "Rain",
                        detail: "On the roof and window",
                        symbolName: "cloud.rain.fill",
                        fileName: "rainy-cabin/rain.m4a",
                        defaultLevel: 0.78
                    ),
                    SoundLayer(
                        id: "thunder",
                        name: "Distant Thunder",
                        detail: "Low and far away",
                        symbolName: "cloud.bolt.fill",
                        fileName: "rainy-cabin/thunder.m4a",
                        defaultLevel: 0.30
                    ),
                    SoundLayer(
                        id: "fireplace",
                        name: "Fireplace",
                        detail: "A quiet, steady crackle",
                        symbolName: "flame.fill",
                        fileName: "rainy-cabin/fireplace.m4a",
                        defaultLevel: 0.55
                    )
                ]
            ),
            SoundEnvironment(
                id: .train,
                name: "Train Compartment",
                tagline: "A warm compartment, moving through the night",
                description: "The rails keep their rhythm while the country slides past the glass.",
                layers: [
                    SoundLayer(
                        id: "rhythm",
                        name: "Rail Rhythm",
                        detail: "Wheels on a steady track",
                        symbolName: "tram.fill",
                        fileName: "train/rhythm.m4a",
                        defaultLevel: 0.72
                    ),
                    SoundLayer(
                        id: "carriage",
                        name: "Carriage",
                        detail: "A warm compartment at night",
                        symbolName: "train.side.front.car",
                        fileName: "train/carriage.m4a",
                        defaultLevel: 0.56
                    ),
                    SoundLayer(
                        id: "horn",
                        name: "Distant Horn",
                        detail: "Far down the line",
                        symbolName: "speaker.wave.2.fill",
                        fileName: "train/horn.m4a",
                        defaultLevel: 0.30
                    )
                ]
            ),
            SoundEnvironment(
                id: .sakuraNight,
                name: "Sakura Night",
                tagline: "Petals, lantern light, and a quiet stream",
                description: "Cherry blossoms drift over a small river while paper lanterns warm the dark.",
                layers: [
                    SoundLayer(
                        id: "petals",
                        name: "Falling Petals",
                        detail: "A soft breeze through blossom",
                        symbolName: "leaf.fill",
                        fileName: "sakura-night/petals.m4a",
                        defaultLevel: 0.66
                    ),
                    SoundLayer(
                        id: "stream",
                        name: "Night Stream",
                        detail: "Water over smooth stones",
                        symbolName: "drop.fill",
                        fileName: "sakura-night/stream.m4a",
                        defaultLevel: 0.52
                    ),
                    SoundLayer(
                        id: "chimes",
                        name: "Lantern Chimes",
                        detail: "Distant glass and koto notes",
                        symbolName: "bell.fill",
                        fileName: "sakura-night/chimes.m4a",
                        defaultLevel: 0.34
                    )
                ]
            ),
            SoundEnvironment(
                id: .cloudLibrary,
                name: "Cloud Library",
                tagline: "Rain on the roof, pages, and warm hush",
                description: "A small library drifting above the clouds, with rain on the glass and nowhere to be.",
                layers: [
                    SoundLayer(
                        id: "window-rain",
                        name: "Window Rain",
                        detail: "Soft rain on an arched roof",
                        symbolName: "cloud.rain.fill",
                        fileName: "cloud-library/window-rain.m4a",
                        defaultLevel: 0.70
                    ),
                    SoundLayer(
                        id: "pages",
                        name: "Turning Pages",
                        detail: "Paper, shelves, and a quiet clock",
                        symbolName: "book.fill",
                        fileName: "cloud-library/pages.m4a",
                        defaultLevel: 0.38
                    ),
                    SoundLayer(
                        id: "hush",
                        name: "Warm Hush",
                        detail: "A low, glowing room tone",
                        symbolName: "sparkles",
                        fileName: "cloud-library/hush.m4a",
                        defaultLevel: 0.48
                    )
                ]
            ),
            SoundEnvironment(
                id: .sunsetDrive,
                name: "Sunset Drive",
                tagline: "A coastal road, a favorite song, and golden light",
                description: "The road curves along the water while a warm song plays and the evening opens ahead.",
                layers: [
                    SoundLayer(
                        id: "road",
                        name: "Open Road",
                        detail: "A steady, quiet drive",
                        symbolName: "car.fill",
                        fileName: "sunset-drive/road.m4a",
                        defaultLevel: 0.56
                    ),
                    SoundLayer(
                        id: "song",
                        name: "Radio Song",
                        detail: "A warm melody on the stereo",
                        symbolName: "music.note",
                        fileName: "sunset-drive/song.m4a",
                        defaultLevel: 0.62
                    ),
                    SoundLayer(
                        id: "air",
                        name: "Coastal Air",
                        detail: "Sea breeze through open windows",
                        symbolName: "wind",
                        fileName: "sunset-drive/air.m4a",
                        defaultLevel: 0.42
                    )
                ]
            ),
            SoundEnvironment(
                id: .seasideRecords,
                name: "Seaside Records",
                tagline: "Vinyl, sea air, and a warm room",
                description: "A small record shop by the water, where dust turns in the light and the tide keeps time.",
                layers: [
                    SoundLayer(
                        id: "vinyl",
                        name: "Vinyl Warmth",
                        detail: "Soft crackle and room hum",
                        symbolName: "opticaldisc.fill",
                        fileName: "seaside-records/vinyl.m4a",
                        defaultLevel: 0.46
                    ),
                    SoundLayer(
                        id: "waves",
                        name: "Ocean Air",
                        detail: "Slow waves beyond the window",
                        symbolName: "water.waves",
                        fileName: "seaside-records/waves.m4a",
                        defaultLevel: 0.68
                    ),
                    SoundLayer(
                        id: "piano",
                        name: "Faint Piano",
                        detail: "A melody from the back room",
                        symbolName: "pianokeys",
                        fileName: "seaside-records/piano.m4a",
                        defaultLevel: 0.34
                    )
                ]
            )
        ])
        return catalog
    }()
}
