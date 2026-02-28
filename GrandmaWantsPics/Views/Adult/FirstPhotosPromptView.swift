import SwiftUI
import PhotosUI

struct FirstPhotosPromptView: View {
    @EnvironmentObject var appVM: AppViewModel

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isLoadingPhotos = false
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var photoCount: Int { selectedImages.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // MARK: Header
                    VStack(spacing: 14) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.pink)

                        Text("Send Grandma a warm welcome")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)

                        Text("She's about to open this app for the very first time. Sending a few photos now means she'll see your family the moment she does — before she even has to ask.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)
                    .padding(.horizontal, 28)

                    if didSend {
                        // MARK: Success state
                        VStack(spacing: 20) {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.pink)

                            Text("Photos sent!")
                                .font(.title2.bold())

                            Text("Grandma is going to love her first look.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                appVM.dismissFirstPhotosPrompt()
                            } label: {
                                Text("Open My Inbox")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.pink.gradient)
                                    .cornerRadius(16)
                            }
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)

                    } else {
                        // MARK: Photo picker + send
                        VStack(spacing: 16) {
                            PhotosPicker(
                                selection: $selectedItems,
                                maxSelectionCount: 10,
                                matching: .images
                            ) {
                                Label(
                                    selectedImages.isEmpty ? "Choose Photos" : "Change Photos",
                                    systemImage: "photo.on.rectangle.angled"
                                )
                                .font(.title3)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.pink.opacity(0.1))
                                .foregroundStyle(.pink)
                                .cornerRadius(14)
                            }
                            .padding(.horizontal, 32)
                            .onChange(of: selectedItems) {
                                isLoadingPhotos = !selectedItems.isEmpty
                                Task { await loadSelectedPhotos() }
                            }

                            if isLoadingPhotos {
                                ProgressView("Loading photos...")
                            }

                            if !selectedImages.isEmpty && !isLoadingPhotos {
                                // Preview strip
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { _, img in
                                            Image(uiImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 90, height: 90)
                                                .clipped()
                                                .cornerRadius(10)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .frame(height: 100)

                                // Nudge toward 2+ photos
                                if photoCount < 2 {
                                    Label(
                                        "2 or more photos make for an especially warm welcome",
                                        systemImage: "sparkles"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                }

                                Button {
                                    Task { await sendPhotos() }
                                } label: {
                                    HStack {
                                        if isSending {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                        }
                                        Text("Send \(photoCount) Photo\(photoCount == 1 ? "" : "s") to Grandma")
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
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !didSend {
                        Button {
                            appVM.dismissFirstPhotosPrompt()
                        } label: {
                            Text("Maybe later")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Loading

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

    // MARK: - Send

    private func sendPhotos() async {
        isSending = true
        errorMessage = nil
        do {
            let dataList = selectedImages.compactMap { downsample($0).jpegData(compressionQuality: 0.8) }
            try await appVM.store.sendPhotos(imageDataList: dataList)
            didSend = true
        } catch {
            errorMessage = "Failed to send: \(error.localizedDescription)"
        }
        isSending = false
    }
}
