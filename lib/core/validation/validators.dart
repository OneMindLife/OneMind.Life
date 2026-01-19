/// Input validation utilities for the OneMind app.
///
/// Provides consistent validation across the app with user-friendly error messages.
library;

import '../errors/errors.dart';

/// Result of a validation check.
class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? field;

  const ValidationResult.valid()
      : isValid = true,
        errorMessage = null,
        field = null;

  const ValidationResult.invalid(this.errorMessage, {this.field})
      : isValid = false;

  /// Convert to AppException if invalid.
  AppException? toException() {
    if (isValid) return null;
    return AppException.validation(
      message: errorMessage ?? 'Validation failed',
      field: field,
    );
  }
}

/// Text input validators.
class TextValidators {
  const TextValidators._();

  /// Validate required field.
  static ValidationResult required(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return ValidationResult.invalid(
        '${fieldName ?? 'This field'} is required',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate minimum length.
  static ValidationResult minLength(
    String? value,
    int minLength, {
    String? fieldName,
  }) {
    if (value == null || value.length < minLength) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Text'} must be at least $minLength characters',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate maximum length.
  static ValidationResult maxLength(
    String? value,
    int maxLength, {
    String? fieldName,
  }) {
    if (value != null && value.length > maxLength) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Text'} must be at most $maxLength characters',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate text within length range.
  static ValidationResult lengthRange(
    String? value, {
    required int min,
    required int max,
    String? fieldName,
  }) {
    final minResult = minLength(value, min, fieldName: fieldName);
    if (!minResult.isValid) return minResult;

    return maxLength(value, max, fieldName: fieldName);
  }

  /// Validate text matches a pattern.
  static ValidationResult pattern(
    String? value,
    RegExp pattern, {
    String? errorMessage,
    String? fieldName,
  }) {
    if (value == null || !pattern.hasMatch(value)) {
      return ValidationResult.invalid(
        errorMessage ?? '${fieldName ?? 'Value'} is invalid',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate email format.
  static ValidationResult email(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return ValidationResult.invalid(
        'Email is required',
        field: fieldName ?? 'email',
      );
    }

    final emailPattern = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailPattern.hasMatch(value)) {
      return ValidationResult.invalid(
        'Please enter a valid email address',
        field: fieldName ?? 'email',
      );
    }

    return const ValidationResult.valid();
  }

  /// Validate chat invite code format.
  static ValidationResult inviteCode(String? value, {String? fieldName}) {
    if (value == null || value.isEmpty) {
      return ValidationResult.invalid(
        'Invite code is required',
        field: fieldName ?? 'inviteCode',
      );
    }

    // Invite codes are uppercase alphanumeric, typically 6-8 characters
    final codePattern = RegExp(r'^[A-Z0-9]{4,10}$');
    final normalized = value.toUpperCase().replaceAll(RegExp(r'\s'), '');

    if (!codePattern.hasMatch(normalized)) {
      return ValidationResult.invalid(
        'Invalid invite code format',
        field: fieldName ?? 'inviteCode',
      );
    }

    return const ValidationResult.valid();
  }

  /// Sanitize user input to prevent XSS and injection.
  static String sanitize(String input) {
    // Remove control characters
    var sanitized = input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Trim excessive whitespace
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Limit length
    if (sanitized.length > 10000) {
      sanitized = sanitized.substring(0, 10000);
    }

    return sanitized;
  }

  /// Check for potentially malicious content.
  static ValidationResult noMaliciousContent(
    String? value, {
    String? fieldName,
  }) {
    if (value == null) return const ValidationResult.valid();

    // Check for script tags
    if (RegExp(r'<script\b', caseSensitive: false).hasMatch(value)) {
      return ValidationResult.invalid(
        'Invalid content detected',
        field: fieldName,
      );
    }

    // Check for SQL injection patterns
    if (RegExp(r"('|--|;|union\s+select|insert\s+into|delete\s+from)",
            caseSensitive: false)
        .hasMatch(value)) {
      return ValidationResult.invalid(
        'Invalid content detected',
        field: fieldName,
      );
    }

    return const ValidationResult.valid();
  }
}

/// Number input validators.
class NumberValidators {
  const NumberValidators._();

  /// Validate number is within range.
  static ValidationResult range(
    num? value, {
    required num min,
    required num max,
    String? fieldName,
  }) {
    if (value == null) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} is required',
        field: fieldName,
      );
    }

    if (value < min || value > max) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} must be between $min and $max',
        field: fieldName,
      );
    }

    return const ValidationResult.valid();
  }

  /// Validate positive number.
  static ValidationResult positive(num? value, {String? fieldName}) {
    if (value == null || value <= 0) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} must be greater than 0',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate non-negative number.
  static ValidationResult nonNegative(num? value, {String? fieldName}) {
    if (value == null || value < 0) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} must be 0 or greater',
        field: fieldName,
      );
    }
    return const ValidationResult.valid();
  }

  /// Validate integer.
  static ValidationResult integer(num? value, {String? fieldName}) {
    if (value == null) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} is required',
        field: fieldName,
      );
    }

    if (value != value.toInt()) {
      return ValidationResult.invalid(
        '${fieldName ?? 'Value'} must be a whole number',
        field: fieldName,
      );
    }

    return const ValidationResult.valid();
  }

  /// Validate credit amount for purchases.
  static ValidationResult credits(int? value, {String? fieldName}) {
    const minCredits = 1;
    const maxCredits = 100000;

    if (value == null) {
      return ValidationResult.invalid(
        'Credit amount is required',
        field: fieldName ?? 'credits',
      );
    }

    if (value < minCredits || value > maxCredits) {
      return ValidationResult.invalid(
        'Credit amount must be between $minCredits and $maxCredits',
        field: fieldName ?? 'credits',
      );
    }

    return const ValidationResult.valid();
  }
}

/// Chat-specific validators.
class ChatValidators {
  const ChatValidators._();

  /// Minimum chat name length.
  static const int minNameLength = 3;

  /// Maximum chat name length.
  static const int maxNameLength = 100;

  /// Maximum initial message length.
  static const int maxInitialMessageLength = 1000;

  /// Maximum proposition content length.
  static const int maxPropositionLength = 500;

  /// Validate chat name.
  static ValidationResult chatName(String? value) {
    final requiredResult = TextValidators.required(value, fieldName: 'Chat name');
    if (!requiredResult.isValid) return requiredResult;

    final lengthResult = TextValidators.lengthRange(
      value,
      min: minNameLength,
      max: maxNameLength,
      fieldName: 'Chat name',
    );
    if (!lengthResult.isValid) return lengthResult;

    return TextValidators.noMaliciousContent(value, fieldName: 'Chat name');
  }

  /// Validate initial message.
  static ValidationResult initialMessage(String? value) {
    final requiredResult = TextValidators.required(
      value,
      fieldName: 'Initial message',
    );
    if (!requiredResult.isValid) return requiredResult;

    final lengthResult = TextValidators.maxLength(
      value,
      maxInitialMessageLength,
      fieldName: 'Initial message',
    );
    if (!lengthResult.isValid) return lengthResult;

    return TextValidators.noMaliciousContent(value, fieldName: 'Initial message');
  }

  /// Validate proposition content.
  static ValidationResult propositionContent(String? value) {
    final requiredResult = TextValidators.required(
      value,
      fieldName: 'Proposition',
    );
    if (!requiredResult.isValid) return requiredResult;

    final lengthResult = TextValidators.lengthRange(
      value,
      min: 1,
      max: maxPropositionLength,
      fieldName: 'Proposition',
    );
    if (!lengthResult.isValid) return lengthResult;

    return TextValidators.noMaliciousContent(value, fieldName: 'Proposition');
  }

  /// Validate timer duration in seconds.
  static ValidationResult timerDuration(int? value, {String? fieldName}) {
    const minSeconds = 30; // 30 seconds minimum
    const maxSeconds = 86400; // 24 hours maximum

    return NumberValidators.range(
      value,
      min: minSeconds,
      max: maxSeconds,
      fieldName: fieldName ?? 'Timer duration',
    );
  }

  /// Validate minimum participants.
  static ValidationResult minimumParticipants(int? value, {String? fieldName}) {
    return NumberValidators.range(
      value,
      min: 1,
      max: 1000,
      fieldName: fieldName ?? 'Minimum participants',
    );
  }

  /// Validate confirmation rounds.
  static ValidationResult confirmationRounds(int? value) {
    return NumberValidators.range(
      value,
      min: 1,
      max: 10,
      fieldName: 'Confirmation rounds',
    );
  }
}

/// Combine multiple validation results.
class ValidationChain {
  final List<ValidationResult> _results = [];

  /// Add a validation result to the chain.
  ValidationChain add(ValidationResult result) {
    _results.add(result);
    return this;
  }

  /// Add a validation result if a condition is met.
  ValidationChain addIf(bool condition, ValidationResult Function() validator) {
    if (condition) {
      _results.add(validator());
    }
    return this;
  }

  /// Get the first validation error, if any.
  ValidationResult get result {
    for (final r in _results) {
      if (!r.isValid) return r;
    }
    return const ValidationResult.valid();
  }

  /// Get all validation errors.
  List<ValidationResult> get errors {
    return _results.where((r) => !r.isValid).toList();
  }

  /// Check if all validations passed.
  bool get isValid => _results.every((r) => r.isValid);
}
