import SwiftUI

private enum GalleryFilter: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    case albums = "Albums"
}

struct GrandmaGalleryView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhoto: Photo?
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var galleryFilter: GalleryFilter = .all
    @State private var selectedAlbum: Album?
    @State private var addToAlbumPhoto: Photo?

    private var fulfilledRequests: [PhotoRequest] {
        appVM.store.requests.filter { $0.status == .fulfilled }
    }

    private var allPhotos: [Photo] {
        let photos = fulfilledRequests.flatMap { appVM.store.photos(for: $0.id) }
        if appVM.isFreeTier {
            return photos.filter { !$0.isExpired }
        }
        return photos
    }

    private var displayedPhotos: [Photo] {
        guard let manager = appVM.galleryDataManager else { return allPhotos }
        switch galleryFilter {
        case .all:
            return allPhotos
        case .favorites:
            return allPhotos.filter { manager.isFavorite($0.id) }
        case .albums:
            guard let album = selectedAlbum else { return [] }
            return manager.photos(in: album, from: allPhotos)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                if appVM.galleryDataManager != nil {
                    Picker("Filter", selection: $galleryFilter) {
                        ForEach(GalleryFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .onChange(of: galleryFilter) { _, _ in
                        selectedAlbum = nil
                    }
                }

                // Content
                Group {
                    if galleryFilter == .albums && selectedAlbum == nil {
                        if let manager = appVM.galleryDataManager {
                            AlbumListView(
                                galleryManager: manager,
                                allPhotos: allPhotos,
                                loadedImages: loadedImages,
                                onSelectAlbum: { album in
                                    selectedAlbum = album
                                }
                            )
                        }
                    } else if displayedPhotos.isEmpty {
                        emptyView
                    } else {
                        photoGrid
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedAlbum != nil {
                        Button {
                            selectedAlbum = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Albums")
                            }
                            .font(.title3)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.title3)
                }
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                GrandmaPhotoViewer(
                    photos: displayedPhotos,
                    initialPhoto: photo,
                    loadedImages: loadedImages,
                    galleryManager: appVM.galleryDataManager
                )
            }
            .sheet(item: $addToAlbumPhoto) { photo in
                if let manager = appVM.galleryDataManager {
                    AddToAlbumSheet(galleryManager: manager, photoId: photo.id)
                }
            }
            .task {
                await loadAllImages()
            }
        }
    }

    private var navigationTitle: String {
        if let album = selectedAlbum {
            return album.name
        }
        return "My Photos"
    }

    private var emptyView: some View {
        Group {
            switch galleryFilter {
            case .all:
                ContentUnavailableView(
                    "No photos yet",
                    systemImage: "photo",
                    description: Text("Your family hasn't sent photos yet.\nTap the big button to ask!")
                )
            case .favorites:
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "heart",
                    description: Text("Tap and hold a photo to add it\nto your favorites.")
                )
            case .albums:
                ContentUnavailableView(
                    "Empty Album",
                    systemImage: "rectangle.stack",
                    description: Text("Open a photo and tap the Album\nbutton to add photos here.")
                )
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 8)
            ], spacing: 8) {
                ForEach(displayedPhotos) { photo in
                    Button {
                        selectedPhoto = photo
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Group {
                                    if let img = loadedImages[photo.id] {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.gray.opacity(0.2)
                                            .overlay(ProgressView())
                                    }
                                }
                            )
                            .overlay(alignment: .topTrailing) {
                                if let manager = appVM.galleryDataManager,
                                   manager.isFavorite(photo.id) {
                                    Image(systemName: "heart.fill")
                                        .font(.title3)
                                        .foregroundStyle(.pink)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                        .padding(8)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let manager = appVM.galleryDataManager {
                            Button {
                                manager.toggleFavorite(photo.id)
                            } label: {
                                Label(
                                    manager.isFavorite(photo.id) ? "Unfavorite" : "Favorite",
                                    systemImage: manager.isFavorite(photo.id) ? "heart.slash" : "heart"
                                )
                            }

                            Button {
                                addToAlbumPhoto = photo
                            } label: {
                                Label("Add to Album", systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func loadAllImages() async {
        for photo in allPhotos where loadedImages[photo.id] == nil {
            if let data = try? await appVM.store.loadImageData(for: photo),
               let img = UIImage(data: data) {
                loadedImages[photo.id] = img
            }
        }
    }
}
