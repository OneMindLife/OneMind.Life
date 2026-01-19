import 'package:flutter/material.dart';

/// Types of legal documents
enum LegalDocumentType {
  privacyPolicy,
  termsOfService,
}

/// Screen for displaying legal documents (Privacy Policy, Terms of Service)
class LegalDocumentScreen extends StatelessWidget {
  final LegalDocumentType documentType;

  const LegalDocumentScreen({
    super.key,
    required this.documentType,
  });

  /// Named constructor for Privacy Policy
  const LegalDocumentScreen.privacyPolicy({super.key})
      : documentType = LegalDocumentType.privacyPolicy;

  /// Named constructor for Terms of Service
  const LegalDocumentScreen.termsOfService({super.key})
      : documentType = LegalDocumentType.termsOfService;

  @override
  Widget build(BuildContext context) {
    final content = _getContent();

    return Scaffold(
      appBar: AppBar(
        title: Text(content.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: ${content.lastUpdated}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 24),
            ...content.sections.map((section) => _buildSection(context, section)),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, LegalSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.heading,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          section.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.6,
              ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  LegalContent _getContent() {
    switch (documentType) {
      case LegalDocumentType.privacyPolicy:
        return _privacyPolicyContent;
      case LegalDocumentType.termsOfService:
        return _termsOfServiceContent;
    }
  }
}

/// Structure for legal document content
class LegalContent {
  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;

  const LegalContent({
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });
}

/// Structure for a section within a legal document
class LegalSection {
  final String heading;
  final String content;

  const LegalSection({
    required this.heading,
    required this.content,
  });
}

// Privacy Policy Content
const _privacyPolicyContent = LegalContent(
  title: 'Privacy Policy',
  lastUpdated: 'January 2026',
  sections: [
    LegalSection(
      heading: '1. Information We Collect',
      content: '''
We collect information you provide directly to us, including:
- Account information (email address, name)
- Content you create within the app (propositions, ratings, chat contributions)
- Usage data and analytics

We also automatically collect certain information when you use our services, including:
- Device information (device type, operating system)
- Log data (access times, pages viewed, app crashes)
- Location data (approximate location based on IP address)
''',
    ),
    LegalSection(
      heading: '2. How We Use Your Information',
      content: '''
We use the information we collect to:
- Provide, maintain, and improve our services
- Process transactions and send related information
- Send technical notices, updates, and support messages
- Respond to your comments and questions
- Analyze usage patterns to improve user experience
- Protect against fraudulent or unauthorized activity
''',
    ),
    LegalSection(
      heading: '3. Information Sharing',
      content: '''
We do not sell your personal information. We may share your information in the following circumstances:
- With your consent
- With service providers who assist in our operations
- To comply with legal obligations
- To protect our rights and the safety of our users
- In connection with a merger or acquisition

Your contributions to public chats may be visible to other participants.
''',
    ),
    LegalSection(
      heading: '4. Data Security',
      content: '''
We implement appropriate security measures to protect your information, including:
- Encryption of data in transit and at rest
- Regular security assessments
- Access controls and authentication requirements
- Secure infrastructure provided by trusted cloud providers

However, no method of transmission over the Internet is 100% secure.
''',
    ),
    LegalSection(
      heading: '5. Your Rights',
      content: '''
Depending on your location, you may have the right to:
- Access the personal information we hold about you
- Request correction of inaccurate information
- Request deletion of your account and associated data
- Object to processing of your information
- Export your data in a portable format

To exercise these rights, contact us at your-email@YOUR_DOMAIN.
''',
    ),
    LegalSection(
      heading: '6. Children\'s Privacy',
      content: '''
Our services are not directed to children under 13. We do not knowingly collect personal information from children under 13. If we learn we have collected such information, we will take steps to delete it.
''',
    ),
    LegalSection(
      heading: '7. Changes to This Policy',
      content: '''
We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date.
''',
    ),
    LegalSection(
      heading: '8. Contact Us',
      content: '''
If you have questions about this Privacy Policy, please contact us at:
OneMind.Life LLC
your-email@YOUR_DOMAIN
''',
    ),
  ],
);

// Terms of Service Content
const _termsOfServiceContent = LegalContent(
  title: 'Terms of Service',
  lastUpdated: 'January 2026',
  sections: [
    LegalSection(
      heading: '1. Acceptance of Terms',
      content: '''
By accessing or using OneMind, you agree to be bound by these Terms of Service and our Privacy Policy. If you do not agree to these terms, do not use our services.

These terms constitute a legally binding agreement between you and OneMind.Life LLC regarding your use of the OneMind application and related services.
''',
    ),
    LegalSection(
      heading: '2. Use of Services',
      content: '''
You may use our services only if you:
- Are at least 13 years old
- Are not barred from using the services under applicable law
- Will comply with these terms and all applicable laws

You are responsible for maintaining the confidentiality of your account credentials and for all activities under your account.
''',
    ),
    LegalSection(
      heading: '3. User Content',
      content: '''
You retain ownership of content you create. By submitting content, you grant us a license to use, display, and distribute it within the service.

You agree not to post content that:
- Violates any law or regulation
- Infringes intellectual property rights
- Contains malware or harmful code
- Is false, misleading, or deceptive
- Is harassing, threatening, or discriminatory
- Promotes violence or illegal activities
''',
    ),
    LegalSection(
      heading: '4. Credits and Payments',
      content: '''
Certain features require credits. Credit purchases are subject to:
- Current pricing at time of purchase
- Non-refundable unless required by law
- Automatic billing if auto-refill is enabled

We reserve the right to modify pricing with reasonable notice. Unused credits do not expire.
''',
    ),
    LegalSection(
      heading: '5. Intellectual Property',
      content: '''
OneMind and its original content, features, and functionality are owned by OneMind.Life LLC and protected by international copyright, trademark, and other intellectual property laws.

Our trademarks may not be used without prior written permission.
''',
    ),
    LegalSection(
      heading: '6. Disclaimers',
      content: '''
THE SERVICES ARE PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND. WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.

We do not warrant that the services will be uninterrupted, secure, or error-free.
''',
    ),
    LegalSection(
      heading: '7. Limitation of Liability',
      content: '''
TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS OR REVENUES.

Our total liability shall not exceed the amount you paid us in the twelve months preceding the claim.
''',
    ),
    LegalSection(
      heading: '8. Termination',
      content: '''
We may terminate or suspend your access at any time, without prior notice, for:
- Violation of these terms
- Fraudulent or illegal activity
- Extended period of inactivity
- Upon your request

Upon termination, your right to use the services ceases immediately.
''',
    ),
    LegalSection(
      heading: '9. Governing Law',
      content: '''
These terms shall be governed by the laws of the State of Wyoming, United States, without regard to conflict of law principles.

Any disputes shall be resolved in the courts of Wyoming.
''',
    ),
    LegalSection(
      heading: '10. Changes to Terms',
      content: '''
We reserve the right to modify these terms at any time. We will notify you of material changes via email or in-app notification.

Continued use after changes constitutes acceptance of the new terms.
''',
    ),
    LegalSection(
      heading: '11. Contact',
      content: '''
For questions about these Terms of Service, contact us at:
OneMind.Life LLC
your-email@YOUR_DOMAIN
''',
    ),
  ],
);
