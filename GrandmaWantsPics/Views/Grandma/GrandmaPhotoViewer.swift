import SwiftUI
import Photos

struct GrandmaPhotoViewer: View {
    let photos: [Photo]
    let initialPhoto: Photo
    let loadedImages: [String: UIImage]
    var galleryManager: GalleryDataManager?

    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0
    @State private var showAddToAlbum = false
    @State private var showSaveConfirmation = false

    private var currentPhoto: Photo? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    if let img = loadedImages[photo.id] {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
                    } else {
                        ProgressView()
                            .tint(.white)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

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

            // Bottom area: counter + action bar
            VStack {
                Spacer()

                Text("\(currentIndex + 1) of \(photos.count)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 8)

                if let manager = galleryManager, let photo = currentPhoto {
                    actionBar(manager: manager, photo: photo)
                        .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 40)
                }
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
                        .padding(.bottom, 140)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut, value: showSaveConfirmation)
            }
        }
        .onAppear {
            if let idx = photos.firstIndex(where: { $0.id == initialPhoto.id }) {
                currentIndex = idx
            }
        }
        .sheet(isPresented: $showAddToAlbum) {
            if let manager = galleryManager, let photo = currentPhoto {
                AddToAlbumSheet(galleryManager: manager, photoId: photo.id)
            }
        }
    }

    private func actionBar(manager: GalleryDataManager, photo: Photo) -> some View {
        HStack(spacing: 32) {
            // Favorite button
            Button {
                manager.toggleFavorite(photo.id)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: manager.isFavorite(photo.id) ? "heart.fill" : "heart")
                        .font(.system(size: 28))
                        .foregroundStyle(manager.isFavorite(photo.id) ? .pink : .white)
                    Text("Favorite")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Save button
            Button {
                saveToPhotos(photo: photo)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                    Text("Save")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Album button
            Button {
                showAddToAlbum = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                    Text("Album")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.6))
        .cornerRadius(20)
    }

    private func saveToPhotos(photo: Photo) {
        guard let image = loadedImages[photo.id] else { return }

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
