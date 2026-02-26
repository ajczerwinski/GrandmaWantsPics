const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const db = getFirestore();

// When Grandma creates a new request, notify the Adult
exports.onNewRequest = onDocumentCreated(
  "families/{familyId}/requests/{requestId}",
  async (event) => {
    const fromRole = event.data.data().fromRole;
    if (fromRole !== "grandma") return;

    const { familyId } = event.params;

    const connectionsSnap = await db
      .collection("families")
      .doc(familyId)
      .collection("connections")
      .where("role", "==", "adult")
      .get();

    const tokens = connectionsSnap.docs
      .map((doc) => doc.data().fcmToken)
      .filter(Boolean);

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: "📸 Grandma wants pictures!",
        body: "She'd love to see this week's moments.",
      },
      data: { type: "new_request" },
      tokens,
    };

    const response = await getMessaging().sendEachForMulticast(message);
    console.log(`Sent to ${response.successCount} of ${tokens.length} adults`);
  }
);

// When a request is fulfilled, notify Grandma
exports.onRequestFulfilled = onDocumentUpdated(
  "families/{familyId}/requests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Only fire when status changes to "fulfilled"
    if (before.status === "fulfilled" || after.status !== "fulfilled") return;

    const { familyId } = event.params;

    const connectionsSnap = await db
      .collection("families")
      .doc(familyId)
      .collection("connections")
      .where("role", "==", "grandma")
      .get();

    const tokens = connectionsSnap.docs
      .map((doc) => doc.data().fcmToken)
      .filter(Boolean);

    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: "🖼️ New photos from family!",
        body: "Open to see what they shared.",
      },
      data: { type: "new_photos" },
      tokens,
    };

    const response = await getMessaging().sendEachForMulticast(message);
    console.log(`Sent to ${response.successCount} of ${tokens.length} grandmas`);
  }
);

// Batch favorites into one notification per 15-minute window
exports.batchFavoriteNotifications = onSchedule("*/5 * * * *", async () => {
  const snap = await db.collectionGroup("pendingFavorites").get();
  if (snap.empty) return;

  const byFamily = {};
  snap.docs.forEach(doc => {
    const familyId = doc.ref.parent.parent.id;
    if (!byFamily[familyId]) byFamily[familyId] = [];
    byFamily[familyId].push(doc);
  });

  for (const [familyId, docs] of Object.entries(byFamily)) {
    const count = docs.length;
    let body;
    if (count === 1)      body = "Grandma loved a photo you shared 💛";
    else if (count <= 5)  body = `Grandma loved ${count} photos you shared 💛`;
    else                  body = "Grandma spent time looking through your photos today 💛";

    const connectionsSnap = await db.collection("families").doc(familyId)
      .collection("connections").where("role", "==", "adult").get();
    const tokens = connectionsSnap.docs.map(d => d.data().fcmToken).filter(Boolean);

    if (tokens.length > 0) {
      await getMessaging().sendEachForMulticast({
        notification: { title: "💛 Grandma loved your photos", body },
        data: { type: "grandma_favorited" },
        tokens,
      });
    }

    const batch = db.batch();
    docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
  }
});

// Immediately notify adults when Grandma creates an album
exports.onAlbumCreated = onDocumentCreated(
  "families/{familyId}/albumEvents/{eventId}",
  async (event) => {
    const { familyId } = event.params;
    const albumName = event.data.data().albumName ?? "a new album";

    const connectionsSnap = await db.collection("families").doc(familyId)
      .collection("connections").where("role", "==", "adult").get();
    const tokens = connectionsSnap.docs.map(d => d.data().fcmToken).filter(Boolean);
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      notification: {
        title: "📸 Grandma created an album",
        body: `She named it "${albumName}"`,
      },
      data: { type: "grandma_album" },
      tokens,
    });
  }
);

// Daily cleanup of expired photos for free-tier families
exports.cleanupExpiredPhotos = onSchedule("every day 02:00", async () => {
  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const bucket = getStorage().bucket();

  let familiesScanned = 0;
  let photosDeleted = 0;
  let errors = 0;

  const familiesSnap = await db
    .collection("families")
    .where("subscriptionTier", "==", "free")
    .get();

  familiesScanned = familiesSnap.size;

  for (const familyDoc of familiesSnap.docs) {
    const requestsSnap = await db
      .collection("families")
      .doc(familyDoc.id)
      .collection("requests")
      .get();

    for (const requestDoc of requestsSnap.docs) {
      const expiredPhotosSnap = await db
        .collection("families")
        .doc(familyDoc.id)
        .collection("requests")
        .doc(requestDoc.id)
        .collection("photos")
        .where("createdAt", "<=", cutoff)
        .get();

      if (expiredPhotosSnap.empty) continue;

      let batch = db.batch();
      let batchCount = 0;

      for (const photoDoc of expiredPhotosSnap.docs) {
        const { storagePath } = photoDoc.data();

        // Delete from Storage
        if (storagePath) {
          try {
            await bucket.file(storagePath).delete();
          } catch (err) {
            if (err.code !== 404) {
              console.error(`Failed to delete storage file ${storagePath}:`, err.message);
              errors++;
            }
          }
        }

        batch.delete(photoDoc.ref);
        batchCount++;
        photosDeleted++;

        // Firestore batches are limited to 500 operations
        if (batchCount === 500) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }
    }
  }

  console.log(
    `Photo TTL cleanup complete: ${familiesScanned} families scanned, ` +
    `${photosDeleted} photos deleted, ${errors} errors`
  );
});
