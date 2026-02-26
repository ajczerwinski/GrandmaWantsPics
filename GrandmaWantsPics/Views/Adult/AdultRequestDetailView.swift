import SwiftUI
import PhotosUI

struct AdultRequestDetailView: View {
    let request: PhotoRequest
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isLoadingPhotos = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var isFulfilled: Bool {
        // Check live store state
        appVM.store.requests.first(where: { $0.id == request.id })?.status == .fulfilled
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Request info
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    Text("Grandma wants pictures!")
                        .font(.title2.bold())
                    Text(request.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if isFulfilled || didSend {
                    // Already fulfilled — show sent photos with TTL badges
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.green)
                        Text("Photos sent!")
                            .font(.title3.bold())
                    }
                    .padding(.top, 20)

                    if appVM.isFreeTier {
                        let photos = appVM.store.photos(for: request.id)
                        let expiringPhotos = photos.filter { !$0.isTrashed && $0.daysUntilExpiry <= 7 }
                        let trashedPhotos = photos.filter { $0.isTrashed && $0.isRecoverable }
                        if let soonest = expiringPhotos.min(by: { $0.daysUntilExpiry < $1.daysUntilExpiry }) {
                            inlineExpiryRow(count: expiringPhotos.count, daysUntilExpiry: soonest.daysUntilExpiry)
                                .padding(.horizontal)
                        }
                        if let soonestTrashed = trashedPhotos.min(by: { ($0.daysUntilPurge ?? 0) < ($1.daysUntilPurge ?? 0) }) {
                            inlineTrashedRow(count: trashedPhotos.count, daysUntilPurge: soonestTrashed.daysUntilPurge ?? 0)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    // Photo picker
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)
                    .onChange(of: selectedItems) {
                        isLoadingPhotos = !selectedItems.isEmpty
                        Task { await loadSelectedPhotos() }
                    }

                    if isLoadingPhotos {
                        ProgressView("Loading photos...")
                            .padding(.top, 20)
                    }

                    // Preview selected
                    if !selectedImages.isEmpty && !isLoadingPhotos {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 110)

                        // Send button
                        Button {
                            Task { await sendPhotos() }
                        } label: {
                            HStack {
                                if isSending {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text("Send \(selectedImages.count) Photo\(selectedImages.count == 1 ? "" : "s")")
                            }
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.pink.gradient)
                            .cornerRadius(16)
                        }
                        .disabled(isSending)
                        .padding(.horizontal, 32)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Spacer()
            }
            .navigationTitle("Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func inlineExpiryRow(count: Int, daysUntilExpiry: Int) -> some View {
        let label = count == 1
            ? "1 photo expires in \(daysUntilExpiry)d"
            : "\(count) photos expire in \(daysUntilExpiry)d"
        return HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private func inlineTrashedRow(count: Int, daysUntilPurge: Int) -> some View {
        let label = count == 1
            ? "1 photo removed · Restorable for \(daysUntilPurge)d"
            : "\(count) photos removed · Restorable for \(daysUntilPurge)d"
        return HStack(spacing: 8) {
            Image(systemName: "trash.circle.fill")
                .foregroundStyle(.pink)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.pink)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.pink.opacity(0.1))
        .cornerRadius(8)
    }

    private func loadSelectedPhotos() async {
        isLoadingPhotos = true
        var images: [UIImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                images.append(img)
            }
        }
        selectedImages = images
        isLoadingPhotos = false
    }

    private func downsample(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        guard scale < 1.0 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private func sendPhotos() async {
        isSending = true
        errorMessage = nil

        do {
            let dataList = selectedImages.compactMap { img in
                downsample(img).jpegData(compressionQuality: 0.8)
            }
            try await appVM.store.fulfillRequest(request.id, imageDataList: dataList)
            didSend = true
            appVM.triggerAccountNudgeIfNeeded()
        } catch {
            errorMessage = "Failed to send: \(error.localizedDescription)"
        }

        isSending = false
    }
}
