// Shared validation utilities for Edge Functions
// Server-side validation to complement client-side checks

export interface ValidationError {
  field: string;
  message: string;
  code: string;
}

export interface ValidationResult {
  valid: boolean;
  errors: ValidationError[];
}

// Validate and sanitize string input
export function validateString(
  value: unknown,
  fieldName: string,
  options: {
    required?: boolean;
    minLength?: number;
    maxLength?: number;
    pattern?: RegExp;
    patternMessage?: string;
  } = {}
): ValidationResult {
  const errors: ValidationError[] = [];
  const { required = true, minLength, maxLength, pattern, patternMessage } = options;

  if (value === undefined || value === null || value === "") {
    if (required) {
      errors.push({
        field: fieldName,
        message: `${fieldName} is required`,
        code: "REQUIRED",
      });
    }
    return { valid: errors.length === 0, errors };
  }

  if (typeof value !== "string") {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a string`,
      code: "INVALID_TYPE",
    });
    return { valid: false, errors };
  }

  const trimmed = value.trim();

  if (minLength !== undefined && trimmed.length < minLength) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be at least ${minLength} characters`,
      code: "MIN_LENGTH",
    });
  }

  if (maxLength !== undefined && trimmed.length > maxLength) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be at most ${maxLength} characters`,
      code: "MAX_LENGTH",
    });
  }

  if (pattern && !pattern.test(trimmed)) {
    errors.push({
      field: fieldName,
      message: patternMessage || `${fieldName} has invalid format`,
      code: "INVALID_FORMAT",
    });
  }

  return { valid: errors.length === 0, errors };
}

// Validate integer input
export function validateInteger(
  value: unknown,
  fieldName: string,
  options: {
    required?: boolean;
    min?: number;
    max?: number;
  } = {}
): ValidationResult {
  const errors: ValidationError[] = [];
  const { required = true, min, max } = options;

  if (value === undefined || value === null || value === "") {
    if (required) {
      errors.push({
        field: fieldName,
        message: `${fieldName} is required`,
        code: "REQUIRED",
      });
    }
    return { valid: errors.length === 0, errors };
  }

  const num = typeof value === "string" ? parseInt(value, 10) : value;

  if (typeof num !== "number" || isNaN(num) || !Number.isInteger(num)) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a valid integer`,
      code: "INVALID_TYPE",
    });
    return { valid: false, errors };
  }

  if (min !== undefined && num < min) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be at least ${min}`,
      code: "MIN_VALUE",
    });
  }

  if (max !== undefined && num > max) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be at most ${max}`,
      code: "MAX_VALUE",
    });
  }

  return { valid: errors.length === 0, errors };
}

// Validate email format
export function validateEmail(
  value: unknown,
  fieldName: string = "email",
  options: { required?: boolean } = {}
): ValidationResult {
  const errors: ValidationError[] = [];
  const { required = true } = options;

  if (value === undefined || value === null || value === "") {
    if (required) {
      errors.push({
        field: fieldName,
        message: `${fieldName} is required`,
        code: "REQUIRED",
      });
    }
    return { valid: errors.length === 0, errors };
  }

  if (typeof value !== "string") {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a string`,
      code: "INVALID_TYPE",
    });
    return { valid: false, errors };
  }

  // RFC 5322 compliant email regex (simplified)
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(value.trim())) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a valid email address`,
      code: "INVALID_EMAIL",
    });
  }

  // Max length check
  if (value.length > 254) {
    errors.push({
      field: fieldName,
      message: `${fieldName} is too long`,
      code: "MAX_LENGTH",
    });
  }

  return { valid: errors.length === 0, errors };
}

// Validate enum value
export function validateEnum<T extends string>(
  value: unknown,
  fieldName: string,
  allowedValues: readonly T[],
  options: { required?: boolean } = {}
): ValidationResult {
  const errors: ValidationError[] = [];
  const { required = true } = options;

  if (value === undefined || value === null || value === "") {
    if (required) {
      errors.push({
        field: fieldName,
        message: `${fieldName} is required`,
        code: "REQUIRED",
      });
    }
    return { valid: errors.length === 0, errors };
  }

  if (typeof value !== "string") {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a string`,
      code: "INVALID_TYPE",
    });
    return { valid: false, errors };
  }

  if (!allowedValues.includes(value as T)) {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be one of: ${allowedValues.join(", ")}`,
      code: "INVALID_ENUM",
    });
  }

  return { valid: errors.length === 0, errors };
}

// Validate Stripe ID format (starts with specific prefix)
export function validateStripeId(
  value: unknown,
  fieldName: string,
  prefix: string,
  options: { required?: boolean } = {}
): ValidationResult {
  const errors: ValidationError[] = [];
  const { required = true } = options;

  if (value === undefined || value === null || value === "") {
    if (required) {
      errors.push({
        field: fieldName,
        message: `${fieldName} is required`,
        code: "REQUIRED",
      });
    }
    return { valid: errors.length === 0, errors };
  }

  if (typeof value !== "string") {
    errors.push({
      field: fieldName,
      message: `${fieldName} must be a string`,
      code: "INVALID_TYPE",
    });
    return { valid: false, errors };
  }

  if (!value.startsWith(prefix)) {
    errors.push({
      field: fieldName,
      message: `${fieldName} has invalid format`,
      code: "INVALID_FORMAT",
    });
  }

  // Stripe IDs are typically alphanumeric with underscores
  const stripeIdRegex = /^[a-zA-Z0-9_]+$/;
  if (!stripeIdRegex.test(value)) {
    errors.push({
      field: fieldName,
      message: `${fieldName} contains invalid characters`,
      code: "INVALID_CHARACTERS",
    });
  }

  return { valid: errors.length === 0, errors };
}

// Combine multiple validation results
export function combineValidations(
  ...results: ValidationResult[]
): ValidationResult {
  const errors: ValidationError[] = [];
  for (const result of results) {
    errors.push(...result.errors);
  }
  return { valid: errors.length === 0, errors };
}

// Sanitize string to prevent injection attacks
export function sanitizeString(input: string): string {
  // Remove null bytes and control characters
  let sanitized = input.replace(/[\x00-\x1F\x7F]/g, "");

  // Normalize whitespace
  sanitized = sanitized.replace(/\s+/g, " ").trim();

  // Truncate to reasonable length
  if (sanitized.length > 10000) {
    sanitized = sanitized.substring(0, 10000);
  }

  return sanitized;
}

// Check for potentially malicious content
export function containsMaliciousContent(input: string): boolean {
  const maliciousPatterns = [
    /<script[^>]*>/i,
    /javascript:/i,
    /on\w+\s*=/i, // onclick=, onerror=, etc.
    /data:text\/html/i,
    /vbscript:/i,
  ];

  return maliciousPatterns.some((pattern) => pattern.test(input));
}

// Format validation errors for API response
export function formatValidationErrors(errors: ValidationError[]): string {
  return errors.map((e) => e.message).join("; ");
}
