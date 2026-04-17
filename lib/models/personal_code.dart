import 'package:equatable/equatable.dart';

enum PersonalCodeStatus { active, reserved, used, revoked }

class PersonalCode extends Equatable {
  final int id;
  final String code;
  final String? label;
  final String? usedBy;
  final DateTime? usedAt;
  final String? reservedBy;
  final DateTime? reservedAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  const PersonalCode({
    required this.id,
    required this.code,
    this.label,
    this.usedBy,
    this.usedAt,
    this.reservedBy,
    this.reservedAt,
    this.revokedAt,
    required this.createdAt,
  });

  PersonalCodeStatus get status {
    if (revokedAt != null) return PersonalCodeStatus.revoked;
    if (usedAt != null) return PersonalCodeStatus.used;
    if (reservedBy != null && reservedAt != null) {
      // Check if reservation is still valid (< 5 min old)
      final age = DateTime.now().difference(reservedAt!);
      if (age.inMinutes < 5) return PersonalCodeStatus.reserved;
    }
    return PersonalCodeStatus.active;
  }

  bool get isActive => status == PersonalCodeStatus.active;

  factory PersonalCode.fromJson(Map<String, dynamic> json) {
    return PersonalCode(
      id: json['id'] as int,
      code: (json['code'] as String).trim(), // CHAR(6) may have trailing spaces
      label: json['label'] as String?,
      usedBy: json['used_by'] as String?,
      usedAt: json['used_at'] != null
          ? DateTime.parse(json['used_at'] as String)
          : null,
      reservedBy: json['reserved_by'] as String?,
      reservedAt: json['reserved_at'] != null
          ? DateTime.parse(json['reserved_at'] as String)
          : null,
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id, code, label, usedBy, usedAt, reservedBy, reservedAt, revokedAt, createdAt];
}
