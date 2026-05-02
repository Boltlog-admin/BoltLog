import 'dart:async';
import '../constants/app_constants.dart';

class RetryService {
  // Retry an operation with exponential backoff
  static Future<T> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = AppConstants.maxRetryAttempts,
    Duration? initialDelay,
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay ?? Duration(seconds: AppConstants.retryDelaySeconds);

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        
        // Check if we should retry this error
        if (shouldRetry != null && !shouldRetry(e)) {
          rethrow;
        }

        // If this was the last attempt, throw the error
        if (attempt >= maxRetries) {
          rethrow;
        }

        // Wait before retrying with exponential backoff
        await Future.delayed(delay);
        delay = Duration(seconds: delay.inSeconds * 2); // Exponential backoff
      }
    }

    throw Exception('Max retries exceeded');
  }

  // Retry with network error detection
  static Future<T> retryOnNetworkError<T>(
    Future<T> Function() operation, {
    int maxRetries = AppConstants.maxRetryAttempts,
  }) async {
    return retryOperation(
      operation,
      maxRetries: maxRetries,
      shouldRetry: (error) {
        final errorString = error.toString().toLowerCase();
        return errorString.contains('network') ||
               errorString.contains('socket') ||
               errorString.contains('timeout') ||
               errorString.contains('connection');
      },
    );
  }
}
