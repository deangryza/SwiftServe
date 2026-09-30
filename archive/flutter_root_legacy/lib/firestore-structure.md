# Firestore collections

workers/{workerId}
worker_verifications/{workerId}
jobs/{jobId}
conversations/{conversationId}
messages/{messageId}
notifications/{notificationId}
reviews/{reviewId}
payments/{paymentId}

Worker profile fields:
name, email, phone, photoUrl, bio, categories[], primarySkills[],
experienceLevel, availability, verificationStatus, verificationBadge,
rating, completedJobs, experienceYears, createdAt, updatedAt

Verification fields:
governmentIdFrontUrl, governmentIdBackUrl, certificates[], proofOfWork[],
status, submittedAt, reviewedAt, reviewedBy

Job fields:
clientId, workerId, service, title, description, location, latitude,
longitude, schedule, price, status, createdAt, acceptedAt, startedAt, completedAt