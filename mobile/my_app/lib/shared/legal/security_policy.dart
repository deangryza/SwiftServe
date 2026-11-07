/// User-supplied policy text; retain placeholders until the owner supplies them.
const swiftServeSecurityPolicy = r'''# SWIFTSERVE
## SECURITY POLICY

**Effective Date:** [Insert Date]  
**Last Updated:** [Insert Date]

SwiftServe is committed to protecting user accounts, personal information, application data, and platform infrastructure.

This Security Policy describes the security practices, user responsibilities, and protective measures intended to help maintain a safe and reliable SwiftServe environment.

## 1. SECURITY OBJECTIVES

SwiftServe aims to protect:

- User accounts and authentication credentials.
- Personal and sensitive information.
- Task descriptions, bookings, and transaction records.
- Uploaded identity verification documents.
- Uploaded images and other application files.
- Administrative accounts and privileges.
- Application infrastructure and backend services.
- The confidentiality, integrity, and availability of platform information.

Security is a shared responsibility between SwiftServe, its administrators, service providers, and users.

## 2. ACCOUNT SECURITY

### 2.1 Authentication

SwiftServe uses authentication mechanisms to establish user identity before granting access to protected features.

Users are responsible for maintaining secure login credentials and protecting their authentication sessions.

### 2.2 Password Protection

Users should:

- Use strong and unique passwords.
- Avoid reusing passwords from other applications.
- Never share passwords with other individuals.
- Avoid storing passwords in publicly accessible locations.
- Change passwords when compromise is suspected.

SwiftServe personnel should never request a user's password through ordinary support communications.

### 2.3 Account Recovery

Account recovery must use authorized authentication and verification procedures.

Users should not provide recovery codes or authentication tokens to untrusted individuals.

### 2.4 Unauthorized Access

Users must report suspected account compromise as soon as reasonably possible.

SwiftServe may temporarily restrict compromised accounts to prevent further unauthorized activity.

## 3. AUTHORIZATION AND ACCESS CONTROL

SwiftServe applies access controls intended to ensure that users can access only information and functionality appropriate to their accounts and permissions.

### 3.1 User Access

Users should only access their own accounts and information or information explicitly made available through authorized platform features.

### 3.2 Administrative Access

Administrative privileges are restricted to authorized personnel.

Administrative access should follow the principle of least privilege, meaning administrators receive only the permissions necessary to perform their responsibilities.

### 3.3 Super Admin Protection

Super Admin functionality is reserved for specifically authorized individuals.

Sensitive administrative actions should be protected through backend authorization checks.

Examples include:

- Creating administrator accounts.
- Assigning or modifying permissions.
- Activating or suspending administrators.
- Managing user restrictions.
- Accessing sensitive administrative records.
- Changing security-sensitive settings.

### 3.4 Privilege Escalation Prevention

SwiftServe intends to prevent unauthorized privilege escalation.

Users and administrators must not attempt to:

- Grant themselves unauthorized privileges.
- Modify their own authorization claims without permission.
- Access restricted administrative endpoints.
- Bypass backend authorization.
- Manipulate account roles or permissions.
- Circumvent Super Admin restrictions.

## 4. DATA PROTECTION

SwiftServe processes personal information according to its Privacy Policy and applicable data protection requirements.

### 4.1 Data Minimization

SwiftServe aims to collect information reasonably necessary for application functionality, security, and legitimate operational purposes.

### 4.2 Confidentiality

Personal information should only be accessed by authorized individuals for legitimate purposes.

### 4.3 Secure Data Transmission

Sensitive information should be transmitted through appropriately protected communication channels.

### 4.4 Data Integrity

SwiftServe uses application controls intended to prevent unauthorized modification, deletion, or manipulation of important records.

### 4.5 Data Retention

Information should be retained only for appropriate operational, security, legal, or legitimate business purposes.

Retention and deletion procedures may vary according to the type of information and applicable requirements.

## 5. IDENTITY DOCUMENTS AND VERIFICATION INFORMATION

SwiftServe may collect identity documents, photographs, or other verification materials when necessary for platform verification.

Users must:

- Submit truthful and authentic information.
- Upload only documents they are authorized to provide.
- Avoid uploading another person's documents without authorization.
- Avoid manipulating or falsifying verification materials.
- Report suspected misuse of identity information.

Verification information is considered sensitive and should receive appropriate protection.

SwiftServe intends to restrict access to verification information to authorized processes and personnel.

Identity verification does not guarantee that a user is trustworthy, safe, or free from criminal history.

## 6. IMAGE AND FILE SECURITY

SwiftServe may allow users to upload profile images, task images, or verification-related files.

The application aims to apply protective measures such as:

- File type validation.
- File size restrictions.
- Image dimension validation.
- Access authorization.
- Ownership checks.
- Restricted file retrieval.
- Retention and deletion controls.
- Protection against unauthorized file access.

Users must not upload:

- Malicious files.
- Unauthorized identity documents.
- Illegal or exploitative content.
- Files intended to compromise the application.
- Content violating another person's privacy or rights.

Users must not attempt to access files belonging to other users without authorization.

## 7. LOCATION AND PERSONAL SAFETY

SwiftServe may use location information to facilitate task matching and other application features.

Users should:

- Avoid sharing unnecessary personal location information.
- Use appropriate privacy settings where available.
- Avoid publicly posting residential addresses unless necessary.
- Verify task locations before accepting arrangements.
- Exercise caution when meeting unfamiliar individuals.
- Report suspicious location-related behavior.

Location information must not be used for stalking, harassment, intimidation, or unauthorized surveillance.

## 8. APPLICATION SECURITY

SwiftServe aims to maintain security through appropriate technical and operational controls.

These may include:

- Authentication middleware.
- Backend authorization checks.
- Input validation.
- Secure configuration management.
- Restricted administrative endpoints.
- Security logging and auditing.
- Dependency monitoring.
- Error handling.
- Protection against unauthorized access.
- Security testing and code review.
- Appropriate service and database permissions.

SwiftServe may periodically review its application and infrastructure for security weaknesses.

## 9. ADMINISTRATIVE SECURITY

Administrative accounts present elevated security risks and require additional safeguards.

SwiftServe intends to:

- Restrict administrator creation to authorized processes.
- Apply role-based access controls.
- Protect Super Admin privileges.
- Record important administrative activities.
- Review suspicious administrative actions.
- Prevent unauthorized permission changes.
- Restrict access to administrative audit records.
- Disable or suspend compromised administrative accounts when appropriate.

Administrators must use their privileges responsibly and only for legitimate platform operations.

Administrative access must not be used to obtain personal information for unauthorized purposes.

## 10. AUDIT LOGGING AND MONITORING

SwiftServe may record security-relevant events to support monitoring, investigation, and accountability.

Examples include:

- Successful and failed authentication attempts.
- Administrative account creation.
- Permission changes.
- Account suspensions and restorations.
- User restrictions.
- Sensitive administrative operations.
- Security-related errors.
- Unauthorized access attempts.

Audit records should be protected against unauthorized modification or deletion.

Access to audit records should be restricted to authorized personnel.

Audit logging does not guarantee that every activity will be recorded or detected.

## 11. INCIDENT RESPONSE

SwiftServe may respond to suspected security incidents through appropriate procedures.

Depending on the circumstances, incident response may include:

1. Identifying and assessing the incident.
2. Restricting affected accounts or services.
3. Investigating the scope and potential impact.
4. Preserving relevant evidence.
5. Correcting identified vulnerabilities.
6. Restoring affected services.
7. Communicating with affected users or authorities when required.
8. Reviewing the incident and implementing improvements.

SwiftServe may temporarily disable affected functionality when necessary to protect users or platform integrity.

## 12. SECURITY INCIDENT REPORTING

Users are encouraged to report security concerns promptly.

Examples include:

- Unauthorized account access.
- Suspicious administrative activity.
- Exposed personal information.
- Unauthorized access to files.
- Fraudulent verification.
- Application vulnerabilities.
- Suspicious login behavior.
- Potential data breaches.
- Security-related abuse.

### Reporting Procedure

Please provide:

- A description of the suspected issue.
- The affected feature or account, if applicable.
- Relevant timestamps.
- Screenshots or evidence, where safe and appropriate.
- Steps to reproduce the issue, if applicable.

Do not include passwords, authentication tokens, private keys, or unnecessary personal information in security reports.

**Security Contact:** [Insert Official Security Email]

SwiftServe may request additional information to investigate a report.

## 13. RESPONSIBLE SECURITY DISCLOSURE

Individuals who identify potential vulnerabilities are encouraged to report them responsibly.

Security researchers should:

- Avoid accessing information belonging to other users.
- Avoid modifying or deleting application data.
- Avoid disrupting application availability.
- Avoid conducting attacks against real users.
- Avoid publicly disclosing vulnerabilities before SwiftServe has had a reasonable opportunity to investigate.
- Avoid using discovered vulnerabilities for unauthorized purposes.

SwiftServe appreciates responsible security reporting but does not currently promise a bug bounty or financial reward unless a separate program is officially established.

## 14. USER SECURITY RESPONSIBILITIES

All users must:

- Keep their accounts secure.
- Protect their personal devices.
- Avoid sharing authentication credentials.
- Use the application responsibly.
- Respect the privacy of other users.
- Avoid suspicious links or requests.
- Report suspected security incidents.
- Avoid exploiting application vulnerabilities.
- Follow applicable laws and platform policies.

Users should maintain updated devices and use trusted networks when accessing sensitive information.

## 15. THIRD-PARTY SERVICES

SwiftServe may rely on third-party services for authentication, hosting, storage, communications, or application infrastructure.

These services may have their own security policies and operational limitations.

SwiftServe seeks to use appropriate security configurations and access controls when integrating third-party services.

However, SwiftServe cannot guarantee the security or uninterrupted availability of third-party infrastructure.

## 16. SECURITY LIMITATIONS

No application, network, or information system can be guaranteed completely secure.

SwiftServe works to reduce security risks through appropriate protective measures but cannot guarantee that:

- Unauthorized access will never occur.
- Every vulnerability will be detected.
- Every malicious activity will be prevented.
- Every uploaded file will be safe.
- Every user will behave responsibly.
- Every security incident will be immediately identified.

Users should exercise reasonable caution when sharing information or interacting with other individuals.

## 17. SECURITY POLICY UPDATES

SwiftServe may revise this Security Policy to reflect:

- Security improvements.
- Changes in application architecture.
- New features.
- Operational requirements.
- Applicable legal or regulatory obligations.

Updated versions may be published through the application or official communication channels.

## 18. CONTACT INFORMATION

For security concerns, suspected vulnerabilities, or unauthorized access:

**SwiftServe Security Team**  
Email: [Insert Official Security Email]

**Privacy Contact:** [Insert Privacy Contact]

**Application Support:** [Insert Official Support Email]

Reports should be submitted through official SwiftServe communication channels.

## 19. ACKNOWLEDGMENT

By using SwiftServe, users acknowledge that they have read and understood this Security Policy and agree to follow the security responsibilities applicable to their use of the platform.''';
