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
        title: "Grandma wants pictures!",
        body: "Tap to send some photos",
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
        title: "New photos!",
        body: "Your family sent you pictures",
      },
      data: { type: "new_photos" },
      tokens,
    };

    const response = await getMessaging().sendEachForMulticast(message);
    console.log(`Sent to ${response.successCount} of ${tokens.length} grandmas`);
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
