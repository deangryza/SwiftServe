# Firestore workflow audit: service request applications

This note records the data and access assumptions used for the request
application workflow. It is intentionally untracked project documentation.

## Collections and access

- `users/{uid}`: private account/profile data. Users read their own record.
  Worker verification is read by rules through the worker's own profile.
- `service_requests/{requestId}`: authenticated users can discover jobs.
  Clients create and cancel their own requests. Clients select an applicant.
  The selected worker alone advances accepted -> ongoing -> completed.
- `service_requests/{requestId}/applications/{workerId}`: a verified worker
  creates one application under their own UID. Only that worker and the request
  owner read it. The request owner accepts one and rejects the others.
- `conversations/{requestId}`: created when the client selects a worker.
  Only the two participants read and update it.
- `conversations/{requestId}/messages/{messageId}`: participants read/create.
- `notifications/{id}`: the application workflow creates notifications only
  between the request client and an applicant/selected worker.
- `worker_verifications/{uid}`, `reviews/{requestId}`,
  `worker_profiles/{uid}`: existing behavior retained.

## Queries

- Requests where `status == pending`
- Requests where `workerId == current worker`
- Requests where `clientId == current client`
- Applications under one request (no cross-request collection-group query)
- Conversations where `participantIds array-contains current user`
- Notifications where `recipientId == current user`
- Messages ordered by `createdAt`

All new application queries use automatic single-field/document indexes.

## Adversarial review

- Anonymous reads/writes remain denied.
- A worker cannot create an application for another worker ID.
- An unverified worker cannot apply.
- A worker cannot apply after a request is assigned or cancelled.
- Duplicate applications are prevented by the worker UID document ID.
- A worker cannot assign themselves by updating a request.
- A client can select only an existing pending applicant for their own request.
- Accepting a request and accepting its application must occur atomically.
- Non-selected applications can only become rejected after assignment.
- Only the selected worker can advance work status.
- Ownership IDs and creation timestamps cannot be changed through updates.
- Application and request strings and numeric fields have bounded sizes/ranges.
- Undefined application fields are rejected.
- Notification creation is tied to an application or accepted request.
- Conversation creation is tied to the selected client/worker pair.

The existing broader rules outside this workflow should receive a separate
full-project security audit before public launch.
