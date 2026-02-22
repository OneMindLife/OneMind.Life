import 'package:equatable/equatable.dart';
import 'proposition.dart';

/// A consensus item wrapping a winning Proposition with its cycle ID.
/// Used to enable host deletion of specific consensus messages.
class ConsensusItem extends Equatable {
  final int cycleId;
  final Proposition proposition;
  final String? taskResult;
  final bool isHostOverride;

  const ConsensusItem({
    required this.cycleId,
    required this.proposition,
    this.taskResult,
    this.isHostOverride = false,
  });

  int get id => proposition.id;
  String get displayContent => proposition.displayContent;

  ConsensusItem copyWith({
    int? cycleId,
    Proposition? proposition,
    String? Function()? taskResult,
    bool? isHostOverride,
  }) {
    return ConsensusItem(
      cycleId: cycleId ?? this.cycleId,
      proposition: proposition ?? this.proposition,
      taskResult: taskResult != null ? taskResult() : this.taskResult,
      isHostOverride: isHostOverride ?? this.isHostOverride,
    );
  }

  @override
  List<Object?> get props => [cycleId, proposition, taskResult, isHostOverride];
}
