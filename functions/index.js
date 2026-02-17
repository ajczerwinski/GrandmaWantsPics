const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

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
      tokens,
    };

    const response = await getMessaging().sendEachForMulticast(message);
    console.log(`Sent to ${response.successCount} of ${tokens.length} grandmas`);
  }
);
