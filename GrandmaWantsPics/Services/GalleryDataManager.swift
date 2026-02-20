import Foundation

struct Album: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var photoIds: [String]
    var createdAt: Date = Date()

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class GalleryDataManager: ObservableObject {
    @Published var favoritePhotoIds: Set<String> = []
    @Published var albums: [Album] = []

    private let familyId: String
    private let defaults = UserDefaults.standard

    private var favoritesKey: String { "favorites_\(familyId)" }
    private var albumsFileName: String { "albums_\(familyId).json" }

    init(familyId: String) {
        self.familyId = familyId
        loadFavorites()
        loadAlbums()
    }

    // MARK: - Favorites

    func isFavorite(_ photoId: String) -> Bool {
        favoritePhotoIds.contains(photoId)
    }

    func toggleFavorite(_ photoId: String) {
        if favoritePhotoIds.contains(photoId) {
            favoritePhotoIds.remove(photoId)
        } else {
            favoritePhotoIds.insert(photoId)
        }
        saveFavorites()
    }

    private func loadFavorites() {
        if let array = defaults.stringArray(forKey: favoritesKey) {
            favoritePhotoIds = Set(array)
        }
    }

    private func saveFavorites() {
        defaults.set(Array(favoritePhotoIds), forKey: favoritesKey)
    }

    // MARK: - Albums

    func createAlbum(name: String) {
        let album = Album(name: name, photoIds: [])
        albums.append(album)
        saveAlbums()
    }

    func renameAlbum(_ albumId: String, to newName: String) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].name = newName
        saveAlbums()
    }

    func deleteAlbum(_ albumId: String) {
        albums.removeAll { $0.id == albumId }
        saveAlbums()
    }

    func addPhoto(_ photoId: String, toAlbum albumId: String) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard !albums[index].photoIds.contains(photoId) else { return }
        albums[index].photoIds.append(photoId)
        saveAlbums()
    }

    func removePhoto(_ photoId: String, fromAlbum albumId: String) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].photoIds.removeAll { $0 == photoId }
        saveAlbums()
    }

    func albumsContaining(_ photoId: String) -> [Album] {
        albums.filter { $0.photoIds.contains(photoId) }
    }

    /// Resolves album photo IDs against live photos, filtering expired/missing ones.
    func photos(in album: Album, from allPhotos: [Photo]) -> [Photo] {
        let photoMap = Dictionary(uniqueKeysWithValues: allPhotos.map { ($0.id, $0) })
        return album.photoIds.compactMap { photoMap[$0] }
    }

    private var albumsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(albumsFileName)
    }

    private func loadAlbums() {
        guard let data = try? Data(contentsOf: albumsFileURL),
              let decoded = try? JSONDecoder().decode([Album].self, from: data) else {
            return
        }
        albums = decoded
    }

    private func saveAlbums() {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        try? data.write(to: albumsFileURL, options: .atomic)
    }
}
