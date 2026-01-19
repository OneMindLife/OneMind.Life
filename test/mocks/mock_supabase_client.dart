import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mock SupabaseClient for testing
class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Mock SupabaseQueryBuilder for testing
class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Mock PostgrestFilterBuilder for testing
class MockPostgrestFilterBuilder<T> extends Mock
    implements PostgrestFilterBuilder<T> {}

/// Mock PostgrestTransformBuilder for testing
class MockPostgrestTransformBuilder<T> extends Mock
    implements PostgrestTransformBuilder<T> {}

/// Mock RealtimeChannel for testing subscriptions
class MockRealtimeChannel extends Mock implements RealtimeChannel {}

/// Mock GoTrueClient for auth testing
class MockGoTrueClient extends Mock implements GoTrueClient {}

/// Mock FunctionsClient for Edge Function testing
class MockFunctionsClient extends Mock implements FunctionsClient {}
