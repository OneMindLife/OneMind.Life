import '../../services/ab_test_service.dart';

/// Marketing copy for a single landing page variant.
class LandingCopy {
  final String headline;
  final String subheadline;
  final String ctaLabel;
  final String benefit1Title;
  final String benefit1Desc;
  final String benefit2Title;
  final String benefit2Desc;
  final String benefit3Title;
  final String benefit3Desc;
  final String closingHeadline;
  final String closingSubheadline;

  const LandingCopy({
    required this.headline,
    required this.subheadline,
    required this.ctaLabel,
    required this.benefit1Title,
    required this.benefit1Desc,
    required this.benefit2Title,
    required this.benefit2Desc,
    required this.benefit3Title,
    required this.benefit3Desc,
    required this.closingHeadline,
    required this.closingSubheadline,
  });
}

/// Returns marketing copy for the given A/B test variant.
LandingCopy getCopy(LandingVariant variant) {
  switch (variant) {
    case LandingVariant.decisions:
      return const LandingCopy(
        headline: 'Make Decisions Your\nTeam Can Trust',
        subheadline:
            'OneMind uses anonymous proposing and transparent rating '
            'to surface the best ideas — no politics, no loudest voice wins.',
        ctaLabel: 'Try It Free',
        benefit1Title: 'No Politics',
        benefit1Desc:
            'Anonymous proposals mean ideas are judged on merit, not '
            'who said them. Everyone gets an equal voice.',
        benefit2Title: 'No Meetings Needed',
        benefit2Desc:
            'Contribute ideas and rate on your own schedule. '
            'Decisions happen asynchronously, whenever your team is ready.',
        benefit3Title: 'Transparent Results',
        benefit3Desc:
            'Watch consensus emerge in real time. Every rating is '
            'fair, every outcome is earned — never imposed.',
        closingHeadline: 'Better decisions start here.',
        closingSubheadline:
            'Join teams already making decisions they can trust.',
      );
    case LandingVariant.consensus:
      return const LandingCopy(
        headline: 'Group Consensus in\nMinutes, Not Meetings',
        subheadline:
            'Skip the back-and-forth. OneMind\'s structured rounds help '
            'groups converge on the best answer — fast and fair.',
        ctaLabel: 'Start for Free',
        benefit1Title: 'Fair by Design',
        benefit1Desc:
            'Everyone proposes anonymously, everyone rates equally. '
            'The process guarantees no single voice dominates.',
        benefit2Title: 'Convergence, Not Compromise',
        benefit2Desc:
            'Ideas compete head-to-head across rounds until the '
            'strongest one wins repeatedly. That\'s real consensus.',
        benefit3Title: 'Works Asynchronously',
        benefit3Desc:
            'No scheduling headaches. Your group participates when '
            'it suits them — convergence happens on its own timeline.',
        closingHeadline: 'Real consensus, not forced agreement.',
        closingSubheadline:
            'See how groups find alignment with OneMind.',
      );
  }
}
