import SwiftUI
import Photos

struct GrandmaPhotoViewer: View {
    let photos: [Photo]
    let initialPhoto: Photo
    let cacheService: ImageCacheService?
    let store: FamilyStore
    var galleryManager: GalleryDataManager?

    @Environment(\.dismiss) var dismiss
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var currentIndex: Int = 0
    @State private var showAddToAlbum = false
    @State private var showSaveConfirmation = false
    @State private var showReportAlert = false
    @State private var showReportConfirmation = false
    @State private var loadedFullImages: [String: UIImage] = [:]

    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var currentPhoto: Photo? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding()
                }
                Spacer()
            }

            // Save confirmation toast
            if showSaveConfirmation {
                VStack {
                    Spacer()
                    Text("Saved to Camera Roll!")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.green.cornerRadius(14))
                        .shadow(radius: 8)
                        .padding(.bottom, isLandscape ? 20 : 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: showSaveConfirmation)
            }

            // Report confirmation toast
            if showReportConfirmation {
                VStack {
                    Spacer()
                    Text("Photo Reported")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.orange.cornerRadius(14))
                        .shadow(radius: 8)
                        .padding(.bottom, isLandscape ? 20 : 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: showReportConfirmation)
            }
        }
        .onAppear {
            if let idx = photos.firstIndex(where: { $0.id == initialPhoto.id }) {
                currentIndex = idx
            }
        }
        .sheet(isPresented: $showAddToAlbum) {
            if let manager = galleryManager, let photo = currentPhoto {
                AddToAlbumSheet(galleryManager: manager, photoId: photo.id, onAlbumCreated: { albumName in
                    Task { try? await store.recordAlbumCreated(albumName: albumName) }
                })
            }
        }
        .alert("Report Photo", isPresented: $showReportAlert) {
            Button("Report as Inappropriate", role: .destructive) {
                guard let photo = currentPhoto else { return }
                Task {
                    try? await store.reportPhoto(photo, fromRequest: photo.requestId)
                    showReportConfirmation = true
                    try? await Task.sleep(for: .seconds(1.5))
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This photo will be flagged for review.")
        }
    }

    // MARK: - Portrait Layout (action bar at bottom)

    private var portraitLayout: some View {
        ZStack {
            photoTabView

            VStack {
                Spacer()

                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 4)

                if let photo = currentPhoto {
                    Text("Sent \(photo.createdAt.formatted(date: .long, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.bottom, 10)

                    if let manager = galleryManager {
                        portraitActionBar(manager: manager, photo: photo)
                            .padding(.bottom, 40)
                    } else {
                        Spacer().frame(height: 40)
                    }
                } else {
                    Spacer().frame(height: 40)
                }
            }
        }
    }

    // MARK: - Landscape Layout (action bar on trailing side)

    private var landscapeLayout: some View {
        HStack(spacing: 0) {
            ZStack {
                photoTabView

                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) of \(photos.count)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 12)
                }
            }

            if let manager = galleryManager, let photo = currentPhoto {
                landscapeActionBar(manager: manager, photo: photo)
            }
        }
    }

    private var photoTabView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                CachedFullSizePage(
                    photo: photo,
                    cacheService: cacheService,
                    store: store,
                    onLoaded: { image in
                        loadedFullImages[photo.id] = image
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    // MARK: - Portrait Action Bar (full-width rows at bottom)

    private func portraitActionBar(manager: GalleryDataManager, photo: Photo) -> some View {
        VStack(spacing: 10) {
            actionButton(
                icon: manager.isFavorite(photo.id) ? "heart.fill" : "heart",
                label: manager.isFavorite(photo.id) ? "Favorited" : "Favorite",
                iconColor: manager.isFavorite(photo.id) ? .pink : .white
            ) {
                let wasAlreadyFavorite = manager.isFavorite(photo.id)
                manager.toggleFavorite(photo.id)
                if !wasAlreadyFavorite {
                    Task { try? await store.recordFavoriteEvent(photoId: photo.id) }
                }
            }

            actionButton(
                icon: "square.and.arrow.down",
                label: "Save to Camera Roll",
                iconColor: .white
            ) {
                saveToPhotos(photo: photo)
            }

            actionButton(
                icon: "rectangle.stack.badge.plus",
                label: "Add to Album",
                iconColor: .white
            ) {
                showAddToAlbum = true
            }

            actionButton(
                icon: "flag",
                label: "Report Photo",
                iconColor: .white
            ) {
                showReportAlert = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.6))
        .cornerRadius(20)
    }

    private func actionButton(icon: String, label: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.body.bold())
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.white.opacity(0.15))
            .cornerRadius(14)
        }
    }

    // MARK: - Landscape Action Bar (compact column on trailing side)

    private func landscapeActionBar(manager: GalleryDataManager, photo: Photo) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Text(photo.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            compactActionButton(
                icon: manager.isFavorite(photo.id) ? "heart.fill" : "heart",
                label: manager.isFavorite(photo.id) ? "Favorited" : "Favorite",
                iconColor: manager.isFavorite(photo.id) ? .pink : .white
            ) {
                let wasAlreadyFavorite = manager.isFavorite(photo.id)
                manager.toggleFavorite(photo.id)
                if !wasAlreadyFavorite {
                    Task { try? await store.recordFavoriteEvent(photoId: photo.id) }
                }
            }

            compactActionButton(
                icon: "square.and.arrow.down",
                label: "Save",
                iconColor: .white
            ) {
                saveToPhotos(photo: photo)
            }

            compactActionButton(
                icon: "rectangle.stack.badge.plus",
                label: "Album",
                iconColor: .white
            ) {
                showAddToAlbum = true
            }

            compactActionButton(
                icon: "flag",
                label: "Report",
                iconColor: .white
            ) {
                showReportAlert = true
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(width: 90)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    private func compactActionButton(icon: String, label: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 66, height: 60)
            .background(.white.opacity(0.15))
            .cornerRadius(12)
        }
    }

    private func saveToPhotos(photo: Photo) {
        guard let image = loadedFullImages[photo.id] else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                if let data = image.jpegData(compressionQuality: 0.95) {
                    request.addResource(with: .photo, data: data, options: nil)
                }
            } completionHandler: { success, _ in
                if success {
                    DispatchQueue.main.async {
                        showSaveConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showSaveConfirmation = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CachedFullSizePage

private struct CachedFullSizePage: View {
    let photo: Photo
    let cacheService: ImageCacheService?
    let store: FamilyStore
    let onLoaded: (UIImage) -> Void

    @State private var fullImage: UIImage?
    @State private var thumbnailImage: UIImage?

    var body: some View {
        Group {
            if let img = fullImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let thumb = thumbnailImage {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: photo.id) {
            guard let cacheService else {
                // Fallback for local demo mode
                if let data = try? await store.loadImageData(for: photo),
                   let img = UIImage(data: data) {
                    fullImage = img
                    onLoaded(img)
                }
                return
            }

            // Load thumbnail first as placeholder
            if let thumb = await cacheService.loadImage(for: photo, thumbnail: true, using: store) {
                if fullImage == nil {
                    thumbnailImage = thumb
                }
            }

            // Then load full-size
            if let full = await cacheService.loadImage(for: photo, thumbnail: false, using: store) {
                fullImage = full
                onLoaded(full)
            }
        }
    }
}
