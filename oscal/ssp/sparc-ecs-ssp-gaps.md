# SSP Gap Report — SPARC ECS Fargate

**Baseline**: NIST SP 800-53 Rev 5 HIGH Impact
**Controls covered**: 160/370 (43.2%)
**Controls not addressed**: 269

## Summary by Responsibility

| Responsibility | Count | Action |
| --- | --- | --- |
| CSP Inherited | 11 | Document CSP inheritance (AWS/Azure) |
| Hybrid | 2 | Shared between CSP and organization |
| IaC / Application | 208 | Add CDEFs or SPARC app coverage |
| Policy | 48 | Organizational policy documentation |
| **Total** | **269** | |

## Gaps by Control Family

### Access Control (39 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ac-1 | Policy and Procedures | Policy |
| ac-10 | Concurrent Session Control | IaC / Application |
| ac-11 | Device Lock | IaC / Application |
| ac-11.1 | Pattern-hiding Displays | IaC / Application |
| ac-14 | Permitted Actions Without Identification or Authentication | IaC / Application |
| ac-17.1 | Monitoring and Control | IaC / Application |
| ac-17.2 | Protection of Confidentiality and Integrity Using Encryption | IaC / Application |
| ac-17.3 | Managed Access Control Points | IaC / Application |
| ac-17.4 | Privileged Commands and Access | IaC / Application |
| ac-18 | Wireless Access | IaC / Application |
| ac-18.1 | Authentication and Encryption | IaC / Application |
| ac-18.3 | Disable Wireless Networking | IaC / Application |
| ac-18.4 | Restrict Configurations by Users | IaC / Application |
| ac-18.5 | Antennas and Transmission Power Levels | IaC / Application |
| ac-19 | Access Control for Mobile Devices | IaC / Application |
| ac-19.5 | Full Device or Container-based Encryption | IaC / Application |
| ac-2.1 | Automated System Account Management | IaC / Application |
| ac-2.11 | Usage Conditions | IaC / Application |
| ac-2.12 | Account Monitoring for Atypical Usage | IaC / Application |
| ac-2.13 | Disable Accounts for High-risk Individuals | IaC / Application |
| ac-2.2 | Automated Temporary and Emergency Account Management | IaC / Application |
| ac-2.3 | Disable Accounts | IaC / Application |
| ac-2.4 | Automated Audit Actions | IaC / Application |
| ac-2.5 | Inactivity Logout | IaC / Application |
| ac-20 | Use of External Systems | IaC / Application |
| ac-20.1 | Limits on Authorized Use | IaC / Application |
| ac-20.2 | Portable Storage Devices — Restricted Use | IaC / Application |
| ac-21 | Information Sharing | IaC / Application |
| ac-22 | Publicly Accessible Content | IaC / Application |
| ac-4.4 | Flow Control of Encrypted Information | IaC / Application |
| ac-5 | Separation of Duties | IaC / Application |
| ac-6.10 | Prohibit Non-privileged Users from Executing Privileged Functions | IaC / Application |
| ac-6.2 | Non-privileged Access for Nonsecurity Functions | IaC / Application |
| ac-6.3 | Network Access to Privileged Commands | IaC / Application |
| ac-6.5 | Privileged Accounts | IaC / Application |
| ac-6.7 | Review of User Privileges | IaC / Application |
| ac-6.9 | Log Use of Privileged Functions | IaC / Application |
| ac-7 | Unsuccessful Logon Attempts | IaC / Application |
| ac-8 | System Use Notification | IaC / Application |

### Assessment, Authorization, and Monitoring (12 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ca-1 | Policy and Procedures | Policy |
| ca-2 | Control Assessments | IaC / Application |
| ca-2.1 | Independent Assessors | IaC / Application |
| ca-2.2 | Specialized Assessments | IaC / Application |
| ca-3.6 | Transfer Authorizations | IaC / Application |
| ca-5 | Plan of Action and Milestones | IaC / Application |
| ca-6 | Authorization | IaC / Application |
| ca-7.1 | Independent Assessment | IaC / Application |
| ca-7.4 | Risk Monitoring | IaC / Application |
| ca-8 | Penetration Testing | IaC / Application |
| ca-8.1 | Independent Penetration Testing Agent or Team | IaC / Application |
| ca-9 | Internal System Connections | IaC / Application |

### Audit and Accountability (18 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| au-1 | Policy and Procedures | Policy |
| au-10 | Non-repudiation | IaC / Application |
| au-12.1 | System-wide and Time-correlated Audit Trail | IaC / Application |
| au-12.3 | Changes by Authorized Individuals | IaC / Application |
| au-3.1 | Additional Audit Information | IaC / Application |
| au-4 | Audit Log Storage Capacity | IaC / Application |
| au-5.1 | Storage Capacity Warning | IaC / Application |
| au-5.2 | Real-time Alerts | IaC / Application |
| au-6.1 | Automated Process Integration | IaC / Application |
| au-6.3 | Correlate Audit Record Repositories | IaC / Application |
| au-6.5 | Integrated Analysis of Audit Records | IaC / Application |
| au-7 | Audit Record Reduction and Report Generation | IaC / Application |
| au-7.1 | Automatic Processing | IaC / Application |
| au-8 | Time Stamps | IaC / Application |
| au-9 | Protection of Audit Information | IaC / Application |
| au-9.2 | Store on Separate Physical Systems or Components | IaC / Application |
| au-9.3 | Cryptographic Protection | IaC / Application |
| au-9.4 | Access by Subset of Privileged Users | IaC / Application |

### Awareness and Training (5 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| at-1 | Policy and Procedures | Policy |
| at-2 | Literacy Training and Awareness | Policy |
| at-2.3 | Social Engineering and Mining | Policy |
| at-3 | Role-based Training | Policy |
| at-4 | Training Records | Policy |

### Configuration Management (26 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| cm-1 | Policy and Procedures | Policy |
| cm-10 | Software Usage Restrictions | IaC / Application |
| cm-12 | Information Location | IaC / Application |
| cm-12.1 | Automated Tools to Support Information Location | IaC / Application |
| cm-2.2 | Automation Support for Accuracy and Currency | IaC / Application |
| cm-2.3 | Retention of Previous Configurations | IaC / Application |
| cm-2.7 | Configure Systems and Components for High-risk Areas | IaC / Application |
| cm-3.1 | Automated Documentation, Notification, and Prohibition of Changes | IaC / Application |
| cm-3.2 | Testing, Validation, and Documentation of Changes | IaC / Application |
| cm-3.4 | Security and Privacy Representatives | IaC / Application |
| cm-3.6 | Cryptography Management | IaC / Application |
| cm-4 | Impact Analyses | IaC / Application |
| cm-4.1 | Separate Test Environments | IaC / Application |
| cm-4.2 | Verification of Controls | IaC / Application |
| cm-5 | Access Restrictions for Change | IaC / Application |
| cm-5.1 | Automated Access Enforcement and Audit Records | IaC / Application |
| cm-6.1 | Automated Management, Application, and Verification | IaC / Application |
| cm-6.2 | Respond to Unauthorized Changes | IaC / Application |
| cm-7.1 | Periodic Review | IaC / Application |
| cm-7.2 | Prevent Program Execution | IaC / Application |
| cm-7.5 | Authorized Software — Allow-by-exception | IaC / Application |
| cm-8.1 | Updates During Installation and Removal | IaC / Application |
| cm-8.2 | Automated Maintenance | IaC / Application |
| cm-8.3 | Automated Unauthorized Component Detection | IaC / Application |
| cm-8.4 | Accountability Information | IaC / Application |
| cm-9 | Configuration Management Plan | IaC / Application |

### Contingency Planning (21 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| cp-1 | Policy and Procedures | Policy |
| cp-10.2 | Transaction Recovery | IaC / Application |
| cp-10.4 | Restore Within Time Period | IaC / Application |
| cp-2.1 | Coordinate with Related Plans | IaC / Application |
| cp-2.2 | Capacity Planning | IaC / Application |
| cp-2.3 | Resume Mission and Business Functions | IaC / Application |
| cp-2.5 | Continue Mission and Business Functions | IaC / Application |
| cp-2.8 | Identify Critical Assets | IaC / Application |
| cp-3 | Contingency Training | IaC / Application |
| cp-3.1 | Simulated Events | IaC / Application |
| cp-4 | Contingency Plan Testing | IaC / Application |
| cp-4.1 | Coordinate with Related Plans | IaC / Application |
| cp-6 | Alternate Storage Site | IaC / Application |
| cp-7 | Alternate Processing Site | IaC / Application |
| cp-7.3 | Priority of Service | IaC / Application |
| cp-8 | Telecommunications Services | IaC / Application |
| cp-9.1 | Testing for Reliability and Integrity | IaC / Application |
| cp-9.2 | Test Restoration Using Sampling | IaC / Application |
| cp-9.3 | Separate Storage for Critical Information | IaC / Application |
| cp-9.5 | Transfer to Alternate Storage Site | IaC / Application |
| cp-9.8 | Cryptographic Protection | IaC / Application |

### Identification and Authentication (20 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ia-1 | Policy and Procedures | Policy |
| ia-12.2 | Identity Evidence | IaC / Application |
| ia-12.3 | Identity Evidence Validation and Verification | IaC / Application |
| ia-12.4 | In-person Validation and Verification | IaC / Application |
| ia-12.5 | Address Confirmation | IaC / Application |
| ia-2.1 | Multi-factor Authentication to Privileged Accounts | IaC / Application |
| ia-2.12 | Acceptance of PIV Credentials | IaC / Application |
| ia-2.2 | Multi-factor Authentication to Non-privileged Accounts | IaC / Application |
| ia-2.5 | Individual Authentication with Group Authentication | IaC / Application |
| ia-2.8 | Access to Accounts — Replay Resistant | IaC / Application |
| ia-3 | Device Identification and Authentication | IaC / Application |
| ia-4 | Identifier Management | IaC / Application |
| ia-4.4 | Identify User Status | IaC / Application |
| ia-5.6 | Protection of Authenticators | IaC / Application |
| ia-6 | Authentication Feedback | IaC / Application |
| ia-7 | Cryptographic Module Authentication | IaC / Application |
| ia-8 | Identification and Authentication (Non-organizational Users) | IaC / Application |
| ia-8.1 | Acceptance of PIV Credentials from Other Agencies | IaC / Application |
| ia-8.2 | Acceptance of External Authenticators | IaC / Application |
| ia-8.4 | Use of Defined Profiles | IaC / Application |

### Incident Response (15 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ir-1 | Policy and Procedures | Policy |
| ir-2 | Incident Response Training | IaC / Application |
| ir-2.1 | Simulated Events | IaC / Application |
| ir-2.2 | Automated Training Environments | IaC / Application |
| ir-3 | Incident Response Testing | IaC / Application |
| ir-3.2 | Coordination with Related Plans | IaC / Application |
| ir-4.1 | Automated Incident Handling Processes | IaC / Application |
| ir-4.11 | Integrated Incident Response Team | IaC / Application |
| ir-4.4 | Information Correlation | IaC / Application |
| ir-5.1 | Automated Tracking, Data Collection, and Analysis | IaC / Application |
| ir-6.1 | Automated Reporting | IaC / Application |
| ir-6.3 | Supply Chain Coordination | IaC / Application |
| ir-7 | Incident Response Assistance | IaC / Application |
| ir-7.1 | Automation Support for Availability of Information and Support | IaC / Application |
| ir-8 | Incident Response Plan | IaC / Application |

### Maintenance (7 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ma-1 | Policy and Procedures | Policy |
| ma-2 | Controlled Maintenance | CSP Inherited |
| ma-3 | Maintenance Tools | CSP Inherited |
| ma-4 | Nonlocal Maintenance | Hybrid |
| ma-4.3 | Comparable Security and Sanitization | Hybrid |
| ma-5 | Maintenance Personnel | CSP Inherited |
| ma-6 | Timely Maintenance | CSP Inherited |

### Media Protection (7 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| mp-1 | Policy and Procedures | Policy |
| mp-2 | Media Access | IaC / Application |
| mp-3 | Media Marking | IaC / Application |
| mp-4 | Media Storage | IaC / Application |
| mp-5 | Media Transport | IaC / Application |
| mp-6.3 | Nondestructive Techniques | IaC / Application |
| mp-7 | Media Use | IaC / Application |

### Personnel Security (9 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ps-1 | Policy and Procedures | Policy |
| ps-2 | Position Risk Designation | Policy |
| ps-3 | Personnel Screening | Policy |
| ps-4 | Personnel Termination | Policy |
| ps-5 | Personnel Transfer | Policy |
| ps-6 | Access Agreements | Policy |
| ps-7 | External Personnel Security | Policy |
| ps-8 | Personnel Sanctions | Policy |
| ps-9 | Position Descriptions | Policy |

### Physical and Environmental Protection (8 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| pe-1 | Policy and Procedures | Policy |
| pe-2 | Physical Access Authorizations | CSP Inherited |
| pe-3 | Physical Access Control | CSP Inherited |
| pe-4 | Access Control for Transmission | CSP Inherited |
| pe-5 | Access Control for Output Devices | CSP Inherited |
| pe-6 | Monitoring Physical Access | CSP Inherited |
| pe-8 | Visitor Access Records | CSP Inherited |
| pe-9 | Power Equipment and Cabling | CSP Inherited |

### Planning (4 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| pl-1 | Policy and Procedures | Policy |
| pl-2 | System Security and Privacy Plans | Policy |
| pl-4 | Rules of Behavior | Policy |
| pl-8 | Security and Privacy Architectures | Policy |

### Risk Assessment (10 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| ra-1 | Policy and Procedures | Policy |
| ra-2 | Security Categorization | Policy |
| ra-3 | Risk Assessment | Policy |
| ra-5 | Vulnerability Monitoring and Scanning | IaC / Application |
| ra-5.11 | Public Disclosure Program | IaC / Application |
| ra-5.2 | Update Vulnerabilities to Be Scanned | IaC / Application |
| ra-5.4 | Discoverable Information | IaC / Application |
| ra-5.5 | Privileged Access | IaC / Application |
| ra-7 | Risk Response | IaC / Application |
| ra-9 | Criticality Analysis | IaC / Application |

### Supply Chain Risk Management (14 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| sr-1 | Policy and Procedures | Policy |
| sr-10 | Inspection of Systems or Components | Policy |
| sr-11 | Component Authenticity | Policy |
| sr-11.1 | Anti-counterfeit Training | Policy |
| sr-11.2 | Configuration Control for Component Service and Repair | Policy |
| sr-12 | Component Disposal | Policy |
| sr-2 | Supply Chain Risk Management Plan | Policy |
| sr-2.1 | Establish SCRM Team | Policy |
| sr-3 | Supply Chain Controls and Processes | Policy |
| sr-5 | Acquisition Strategies, Tools, and Methods | Policy |
| sr-6 | Supplier Assessments and Reviews | Policy |
| sr-8 | Notification Agreements | Policy |
| sr-9 | Tamper Resistance and Detection | Policy |
| sr-9.1 | Multiple Stages of System Development Life Cycle | Policy |

### System and Communications Protection (15 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| sc-1 | Policy and Procedures | Policy |
| sc-10 | Network Disconnect | IaC / Application |
| sc-15 | Collaborative Computing Devices and Applications | IaC / Application |
| sc-18 | Mobile Code | IaC / Application |
| sc-2 | Separation of System and User Functionality | IaC / Application |
| sc-24 | Fail in Known State | IaC / Application |
| sc-28.1 | Cryptographic Protection | IaC / Application |
| sc-3 | Security Function Isolation | IaC / Application |
| sc-39 | Process Isolation | IaC / Application |
| sc-4 | Information in Shared System Resources | IaC / Application |
| sc-7.18 | Fail Secure | IaC / Application |
| sc-7.3 | Access Points | IaC / Application |
| sc-7.4 | External Telecommunications Services | IaC / Application |
| sc-7.7 | Split Tunneling for Remote Devices | IaC / Application |
| sc-7.8 | Route Traffic to Authenticated Proxy Servers | IaC / Application |

### System and Information Integrity (20 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| si-1 | Policy and Procedures | Policy |
| si-11 | Error Handling | IaC / Application |
| si-12 | Information Management and Retention | IaC / Application |
| si-16 | Memory Protection | IaC / Application |
| si-2.2 | Automated Flaw Remediation Status | IaC / Application |
| si-4.10 | Visibility of Encrypted Communications | IaC / Application |
| si-4.12 | Automated Organization-generated Alerts | IaC / Application |
| si-4.2 | Automated Tools and Mechanisms for Real-time Analysis | IaC / Application |
| si-4.20 | Privileged Users | IaC / Application |
| si-4.22 | Unauthorized Network Services | IaC / Application |
| si-4.4 | Inbound and Outbound Communications Traffic | IaC / Application |
| si-5.1 | Automated Alerts and Advisories | IaC / Application |
| si-6 | Security and Privacy Function Verification | IaC / Application |
| si-7.1 | Integrity Checks | IaC / Application |
| si-7.15 | Code Authentication | IaC / Application |
| si-7.2 | Automated Notifications of Integrity Violations | IaC / Application |
| si-7.5 | Automated Response to Integrity Violations | IaC / Application |
| si-7.7 | Integration of Detection and Response | IaC / Application |
| si-8 | Spam Protection | IaC / Application |
| si-8.2 | Automatic Updates | IaC / Application |

### System and Services Acquisition (19 controls)

| Control | Title | Responsibility |
| --- | --- | --- |
| sa-1 | Policy and Procedures | Policy |
| sa-10 | Developer Configuration Management | IaC / Application |
| sa-15.3 | Criticality Analysis | IaC / Application |
| sa-16 | Developer-provided Training | IaC / Application |
| sa-17 | Developer Security and Privacy Architecture and Design | IaC / Application |
| sa-2 | Allocation of Resources | IaC / Application |
| sa-21 | Developer Screening | IaC / Application |
| sa-22 | Unsupported System Components | IaC / Application |
| sa-3 | System Development Life Cycle | IaC / Application |
| sa-4 | Acquisition Process | IaC / Application |
| sa-4.1 | Functional Properties of Controls | IaC / Application |
| sa-4.10 | Use of Approved PIV Products | IaC / Application |
| sa-4.2 | Design and Implementation Information for Controls | IaC / Application |
| sa-4.5 | System, Component, and Service Configurations | IaC / Application |
| sa-4.9 | Functions, Ports, Protocols, and Services in Use | IaC / Application |
| sa-5 | System Documentation | IaC / Application |
| sa-8 | Security and Privacy Engineering Principles | IaC / Application |
| sa-9 | External System Services | IaC / Application |
| sa-9.2 | Identification of Functions, Ports, Protocols, and Services | IaC / Application |

