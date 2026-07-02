const admin = require('firebase-admin');
const fs = require('fs');
const { createObjectCsvWriter } = require('csv-writer');

// IMPORTANT: Download your service account key from the Firebase Console
// (Project Settings -> Service Accounts -> Generate new private key)
// and save it as 'serviceAccountKey.json' in this directory.
const serviceAccountPath = './serviceAccountKey.json';

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`ERROR: Service account key not found at ${serviceAccountPath}`);
  console.error('Please download it from the Firebase Console and save it as serviceAccountKey.json');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function exportFeedbacks() {
  console.log('Fetching feedbacks from Firestore...');
  
  try {
    const snapshot = await db.collection('feedbacks').orderBy('timestamp', 'desc').get();
    
    if (snapshot.empty) {
      console.log('No feedbacks found.');
      return;
    }

    const records = [];
    
    snapshot.forEach(doc => {
      const data = doc.data();
      records.push({
        id: doc.id,
        timestamp: data.timestamp ? data.timestamp.toDate().toISOString() : '',
        category: data.category || '',
        rating: data.rating || '',
        comments: data.comments || '',
        status: data.status || 'new',
        hasAttachment: data.hasAttachment ? 'Yes' : 'No',
        imageUrl: data.imageUrl || '',
        userId: data.userId || 'anonymous'
      });
    });

    const csvWriter = createObjectCsvWriter({
      path: 'feedbacks_export.csv',
      header: [
        { id: 'id', title: 'DOCUMENT_ID' },
        { id: 'timestamp', title: 'TIMESTAMP' },
        { id: 'category', title: 'CATEGORY' },
        { id: 'rating', title: 'RATING' },
        { id: 'comments', title: 'COMMENTS' },
        { id: 'status', title: 'STATUS' },
        { id: 'hasAttachment', title: 'HAS_ATTACHMENT' },
        { id: 'imageUrl', title: 'IMAGE_URL' },
        { id: 'userId', title: 'USER_ID' }
      ]
    });

    console.log(`Found ${records.length} feedbacks. Writing to feedbacks_export.csv...`);
    await csvWriter.writeRecords(records);
    console.log('Export complete! Check feedbacks_export.csv');
    
  } catch (error) {
    console.error('Error exporting feedbacks:', error);
  }
}

exportFeedbacks();
