import SwiftUI

struct AddToAlbumSheet: View {
    @ObservedObject var galleryManager: GalleryDataManager
    let photoId: String
    @Environment(\.dismiss) var dismiss

    @State private var showNewAlbumAlert = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    newAlbumName = ""
                    showNewAlbumAlert = true
                } label: {
                    Label("New Album", systemImage: "plus.circle.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.pink)
                }

                ForEach(galleryManager.albums) { album in
                    let contains = album.photoIds.contains(photoId)
                    Button {
                        if contains {
                            galleryManager.removePhoto(photoId, fromAlbum: album.id)
                        } else {
                            galleryManager.addPhoto(photoId, toAlbum: album.id)
                        }
                    } label: {
                        HStack {
                            Text(album.name)
                                .font(.title3)
                                .foregroundStyle(.primary)
                            Spacer()
                            if contains {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.pink)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.title3.bold())
                }
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
        .presentationDetents([.medium])
    }
}
