import SwiftUI
import PhotosUI

struct AdultSendPhotosView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var didSend = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.pink)
                    Text("Send photos to Grandma")
                        .font(.title2.bold())
                }
                .padding(.top, 24)

                if didSend {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.green)
                        Text("Photos sent!")
                            .font(.title3.bold())
                    }
                    .padding(.top, 20)
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
                        Task { await loadSelectedPhotos() }
                    }

                    // Preview selected
                    if !selectedImages.isEmpty {
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
            .navigationTitle("Send Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func loadSelectedPhotos() async {
        var images: [UIImage] = []
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                images.append(img)
            }
        }
        selectedImages = images
    }

    private func sendPhotos() async {
        isSending = true
        errorMessage = nil

        do {
            let dataList = selectedImages.compactMap { img in
                img.jpegData(compressionQuality: 0.8)
            }
            try await appVM.store.sendPhotos(imageDataList: dataList)
            didSend = true
            appVM.triggerAccountNudgeIfNeeded()
        } catch {
            errorMessage = "Failed to send: \(error.localizedDescription)"
        }

        isSending = false
    }
}
