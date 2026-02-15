# GrandmaWantsPics

A simple iOS app where Grandma taps one button to request photos, and family members respond by picking and sending pictures from their library.

## Architecture

- **SwiftUI**, iOS 17+, iPhone + iPad
- **MVVM-ish**: Models, Services (FamilyStore protocol), ViewModels, Views
- **Two phases**: Phase 0 (local demo) and Phase 1 (Firebase cross-device)
- Single app with two roles: **Grandma** and **Adult (Family)**

## Phase 0 — Local Demo Mode (No Firebase)

Everything runs on-device. Data is stored locally via JSON file persistence. No backend setup required.

### How to Run

1. Open `GrandmaWantsPics.xcodeproj` in Xcode 15+.
2. Select an iPhone or iPad simulator (iOS 17+).
3. Build and run.
4. No `GoogleService-Info.plist` needed — the app auto-detects its absence and uses local mode.

### How to Demo the Full Flow

1. **Launch** — tap **"I'm Grandma"** on the role selection screen.
2. **Request** — tap the big pink **"Send me pictures!"** button. A request is created locally.
3. **Switch role** — there's no gear icon on Grandma's screen by design. Kill and relaunch, or:
   - On the Adult screen, tap the **gear icon** (top-right) → **Switch to Grandma** (or vice versa).
   - To get to Adult the first time, go to the gear menu or reset the app.
   - Quick shortcut: tap gear → **Reset App** → choose **"I'm Family"**.
4. **Fulfill** — in the Adult inbox, tap the pending request → **Choose Photos** → select 1–5 photos → **Send**.
5. **View** — switch back to Grandma → tap **View Photos** → browse the gallery and tap any photo for full-screen paging viewer.

### Pairing (Local Mode)

In local demo mode, pairing is auto-completed. If you manually trigger the pairing flow, the code is always `1234`.

## Phase 1 — Firebase (Cross-Device)

Enables real pairing and photo delivery across two physical devices.

### Firebase Setup Steps

1. Go to [Firebase Console](https://console.firebase.google.com/) and create a new project.
2. Add an iOS app with bundle ID: `com.grandmawantspics.GrandmaWantsPics`.
3. Download `GoogleService-Info.plist` and drag it into the `GrandmaWantsPics/` folder in Xcode (ensure "Copy items if needed" is checked and the app target is selected).
4. Enable **Authentication**:
   - Go to Authentication → Sign-in method → enable **Anonymous**.
   - (Optional) Enable **Sign in with Apple** if you want adult accounts tied to Apple ID.
5. Enable **Cloud Firestore**:
   - Create a database (start in test mode for development).
6. Enable **Firebase Storage**:
   - Create a default bucket (test mode rules for development).
7. Add Firebase SDK via **Swift Package Manager**:
   - In Xcode: File → Add Package Dependencies
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Select: `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`
8. In `GrandmaWantsPicsApp.swift`, add:
   ```swift
   import FirebaseCore

   // Inside init() or App body:
   FirebaseApp.configure()
   ```
9. In `FirebaseFamilyStore.swift`, uncomment the full implementation.
10. Update `AppViewModel.swift` to use `FirebaseFamilyStore` when `AppConfig.useFirebase` is true.

### Firestore Data Model

```
families/{familyId}
  ├── createdAt, createdByUserId, pairingCode
  ├── connections/{connectionId}
  │   └── userId, role, createdAt, fcmToken?
  └── requests/{requestId}
      ├── createdAt, createdByUserId, fromRole, status, fulfilledAt?, fulfilledByUserId?
      └── photos/{photoId}
          └── createdAt, createdByUserId, storagePath
```

### Storage Structure

```
families/{familyId}/requests/{requestId}/{photoId}.jpg
```

### Push Notifications (Optional / Future)

- Configure APNs key in Apple Developer portal.
- Upload APNs auth key to Firebase Console → Project Settings → Cloud Messaging.
- Add `FirebaseMessaging` SPM package.
- Store FCM token on the adult's connection document.
- Use Cloud Functions or a lightweight server to send push when a new request document is created.

### Firestore Security Rules (Starting Point)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /families/{familyId}/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Tighten these before production — restrict access to family members only by checking the connections subcollection.

## File Structure

```
GrandmaWantsPics/
├── App/
│   ├── GrandmaWantsPicsApp.swift    # Entry point
│   ├── AppConfig.swift              # Phase 0/1 toggle (auto-detects Firebase)
│   └── ContentView.swift            # Root router
├── Models/
│   ├── AppRole.swift                # grandma | adult
│   ├── Family.swift
│   ├── PhotoRequest.swift
│   └── Photo.swift
├── Services/
│   ├── FamilyStore.swift            # Protocol
│   ├── LocalFamilyStore.swift       # Phase 0 implementation
│   └── FirebaseFamilyStore.swift    # Phase 1 implementation (commented out)
├── ViewModels/
│   └── AppViewModel.swift           # App-wide state + role management
├── Views/
│   ├── RoleSelectionView.swift      # First-launch role picker
│   ├── Grandma/
│   │   ├── GrandmaHomeView.swift    # Big request button
│   │   ├── GrandmaGalleryView.swift # Photo grid
│   │   └── GrandmaPhotoViewer.swift # Full-screen paging viewer
│   ├── Adult/
│   │   ├── AdultInboxView.swift     # Request list
│   │   └── AdultRequestDetailView.swift # Photo picker + send
│   └── Pairing/
│       └── PairingView.swift        # Code generation / entry
└── Assets.xcassets/
```
