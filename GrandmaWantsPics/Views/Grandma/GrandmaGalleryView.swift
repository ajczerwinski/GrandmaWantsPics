import SwiftUI

struct GrandmaGalleryView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhoto: Photo?
    @State private var loadedImages: [String: UIImage] = [:]

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

    var body: some View {
        NavigationStack {
            Group {
                if allPhotos.isEmpty {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo",
                        description: Text("Your family hasn't sent photos yet.\nTap the big button to ask!")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 150), spacing: 8)
                        ], spacing: 8) {
                            ForEach(allPhotos) { photo in
                                Button {
                                    selectedPhoto = photo
                                } label: {
                                    if let img = loadedImages[photo.id] {
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(minHeight: 150)
                                            .clipped()
                                            .cornerRadius(12)
                                    } else {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 150)
                                            .overlay(ProgressView())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.title3)
                }
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                GrandmaPhotoViewer(photos: allPhotos, initialPhoto: photo, loadedImages: loadedImages)
            }
            .task {
                await loadAllImages()
            }
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
