import 'package:equatable/equatable.dart';

/// Steps in the home screen tour flow.
/// Body elements top-to-bottom first, then app bar buttons left-to-right.
enum HomeTourStep {
  welcomeName,
  searchBar,
  pendingRequest,
  yourChats,
  createFab,
  exploreButton,
  languageSelector,
  howItWorks,
  legalDocs,
  complete,
}

/// State for the home screen tour
class HomeTourState extends Equatable {
  final HomeTourStep currentStep;
  final int stepIndex;
  final int totalSteps;

  static const int total = 9;

  const HomeTourState({
    this.currentStep = HomeTourStep.welcomeName,
    this.stepIndex = 0,
    this.totalSteps = total,
  });

  HomeTourState copyWith({HomeTourStep? currentStep, int? stepIndex}) {
    return HomeTourState(
      currentStep: currentStep ?? this.currentStep,
      stepIndex: stepIndex ?? this.stepIndex,
      totalSteps: totalSteps,
    );
  }

  @override
  List<Object?> get props => [currentStep, stepIndex, totalSteps];
}
