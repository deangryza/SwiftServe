export const VERIFICATION_STATUS = {
  PENDING: 'pending',
  UNDER_REVIEW: 'under_review',
  VERIFIED: 'verified',
  REJECTED: 'rejected',
  RESUBMISSION_REQUIRED: 'resubmission_required',
};

export const ID_TYPES = [
  'Philippine National ID',
  "Driver's License",
  'UMID',
  'Postal ID',
  "Voter's ID",
];

export const formatVerificationStatus = (status) =>
  status
    ? status
        .replaceAll('_', ' ')
        .replace(/\b\w/g, (letter) => letter.toUpperCase())
    : 'Unknown';
