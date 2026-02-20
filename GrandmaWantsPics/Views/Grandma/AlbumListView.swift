import SwiftUI

struct AlbumListView: View {
    @ObservedObject var galleryManager: GalleryDataManager
    let allPhotos: [Photo]
    let cacheService: ImageCacheService?
    let store: FamilyStore
    let onSelectAlbum: (Album) -> Void

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button {
                    newAlbumName = ""
                    showNewAlbumAlert = true
                } label: {
                    Label("New Album", systemImage: "plus.circle.fill")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink.opacity(0.15))
                        .foregroundStyle(.pink)
                        .cornerRadius(16)
                }
                .padding(.horizontal)

                if galleryManager.albums.isEmpty {
                    ContentUnavailableView(
                        "No Albums Yet",
                        systemImage: "rectangle.stack",
                        description: Text("Tap \"New Album\" to create one\nand organize your favorite photos.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(galleryManager.albums) { album in
                            let albumPhotos = galleryManager.photos(in: album, from: allPhotos)
                            Button {
                                onSelectAlbum(album)
                            } label: {
                                AlbumRow(
                                    album: album,
                                    photoCount: albumPhotos.count,
                                    coverPhoto: album.photoIds.first.flatMap { id in allPhotos.first { $0.id == id } },
                                    cacheService: cacheService,
                                    store: store
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    galleryManager.deleteAlbum(album.id)
                                } label: {
                                    Label("Delete Album", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top)
        }
        .alert("New Album", isPresented: $showNewAlbumAlert) {
            TextField("Album name", text: $newAlbumName)
            Button("Create") {
                let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                galleryManager.createAlbum(name: name)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for your new album.")
        }
    }
}

// MARK: - AlbumRow

private struct AlbumRow: View {
    let album: Album
    let photoCount: Int
    let coverPhoto: Photo?
    let cacheService: ImageCacheService?
    let store: FamilyStore

    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            // Cover thumbnail
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipped()
                    .cornerRadius(10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Text("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .task(id: coverPhoto?.id) {
            guard let photo = coverPhoto else { return }
            if let cacheService {
                coverImage = await cacheService.loadImage(for: photo, thumbnail: true, using: store)
            } else {
                if let data = try? await store.loadImageData(for: photo) {
                    coverImage = UIImage(data: data)
                }
            }
        }
    }
}
