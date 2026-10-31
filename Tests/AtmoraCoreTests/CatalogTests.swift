import Testing
@testable import AtmoraCore

@Suite("Ambience catalogue")
struct CatalogTests {
    private let catalog = EnvironmentCatalog.standard

    @Test("Every ambience is declared exactly once")
    func everyEnvironmentIsPresent() {
        #expect(EnvironmentID.allCases.count == 6)
        #expect(catalog.environments.count == 6)
        #expect(Set(catalog.environments.map(\.id)) == Set(EnvironmentID.allCases))
    }

    @Test("Catalogue integrity checks pass")
    func catalogueIsValid() {
        #expect(catalog.integrityIssues.isEmpty)
        #expect(Set(catalog.allLayerFileNames).count == catalog.allLayerFileNames.count)
    }

    @Test("Every ambience has audible layers and complete metadata")
    func everyEnvironmentHasLayers() {
        for environment in catalog.environments {
            #expect(!environment.name.isEmpty)
            #expect(!environment.tagline.isEmpty)
            #expect(!environment.description.isEmpty)
            #expect(!environment.layers.isEmpty)
            #expect(Set(environment.layers.map(\.id)).count == environment.layers.count)

            for layer in environment.layers {
                #expect(!layer.name.isEmpty)
                #expect(!layer.detail.isEmpty)
                #expect(!layer.symbolName.isEmpty)
                #expect(layer.fileName.hasSuffix(".m4a"))
                #expect(!layer.fileName.contains(".."))
                #expect((0.05...1).contains(layer.defaultLevel))
            }
        }
    }

    @Test("Eighteen unique audio files back six ambiences")
    func audioFilesAreUnique() {
        #expect(catalog.allLayerFileNames.count == 18)
        for environment in catalog.environments {
            #expect(environment.layers.count == 3, "\(environment.id.rawValue)")
        }
    }

    @Test("Preset levels match the shipped mix")
    func presetLevels() {
        let rainy = catalog[.rainyCabin]!.defaultLevels
        #expect(rainy["rain"] == 0.78)
        #expect(rainy["thunder"] == 0.30)
        #expect(rainy["fireplace"] == 0.55)

        let train = catalog[.train]!.defaultLevels
        #expect(train["rhythm"] == 0.72)
        #expect(train["carriage"] == 0.56)
        #expect(train["horn"] == 0.30)

        let sakura = catalog[.sakuraNight]!.defaultLevels
        #expect(sakura["petals"] == 0.66)
        #expect(sakura["stream"] == 0.52)
        #expect(sakura["chimes"] == 0.34)

        let library = catalog[.cloudLibrary]!.defaultLevels
        #expect(library["window-rain"] == 0.70)
        #expect(library["pages"] == 0.38)
        #expect(library["hush"] == 0.48)

        let sunset = catalog[.sunsetDrive]!.defaultLevels
        #expect(sunset["road"] == 0.56)
        #expect(sunset["song"] == 0.62)
        #expect(sunset["air"] == 0.42)

        let seaside = catalog[.seasideRecords]!.defaultLevels
        #expect(seaside["vinyl"] == 0.46)
        #expect(seaside["waves"] == 0.68)
        #expect(seaside["piano"] == 0.34)
    }

    @Test("Ambience identifiers remain stable persistence keys")
    func stableIdentifiers() {
        #expect(EnvironmentID.rainyCabin.rawValue == "rainy-cabin")
        #expect(EnvironmentID.train.rawValue == "train")
        #expect(EnvironmentID.sakuraNight.rawValue == "sakura-night")
        #expect(EnvironmentID.cloudLibrary.rawValue == "cloud-library")
        #expect(EnvironmentID.sunsetDrive.rawValue == "sunset-drive")
        #expect(EnvironmentID.seasideRecords.rawValue == "seaside-records")
    }

    @Test("Display names match the shipped catalogue")
    func displayNames() {
        #expect(catalog[.rainyCabin]!.name == "Rainy Cabin")
        #expect(catalog[.train]!.name == "Train Compartment")
        #expect(catalog[.sakuraNight]!.name == "Sakura Night")
        #expect(catalog[.cloudLibrary]!.name == "Cloud Library")
        #expect(catalog[.sunsetDrive]!.name == "Sunset Drive")
        #expect(catalog[.seasideRecords]!.name == "Seaside Records")
    }

    @Test("Shortcuts map to every ambience in catalogue order")
    func shortcutOrder() {
        #expect(EnvironmentID.allCases.map(\.rawValue) == [
            "rainy-cabin", "train", "sakura-night", "cloud-library",
            "sunset-drive", "seaside-records"
        ])
    }
}
