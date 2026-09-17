import '../error/failures.dart';

/// A sealed class representing the result of an operation that can either succeed or fail.
abstract class Result<T, E extends Failure> {
  const Result();

  /// Creates a success result with the given [value].
  factory Result.success(T value) = Success<T, E>;

  /// Creates a failure result with the given [failure].
  factory Result.failure(E failure) = FailureResult<T, E>;

  /// Returns `true` if this is a [Success] result.
  bool get isSuccess => this is Success<T, E>;

  /// Returns `true` if this is a [FailureResult] result.
  bool get isFailure => this is FailureResult<T, E>;

  /// Returns the value of a [Success] result or `null` if it is a [FailureResult].
  T? get value => isSuccess ? (this as Success<T, E>).value : null;

  /// Returns the failure of a [FailureResult] result or `null` if it is a [Success].
  E? get failure => isFailure ? (this as FailureResult<T, E>).failure : null;
}

/// Represents a successful result.
class Success<T, E extends Failure> extends Result<T, E> {
  @override
  final T value;

  const Success(this.value);
}

/// Represents a failure result.
class FailureResult<T, E extends Failure> extends Result<T, E> {
  @override
  final E failure;

  const FailureResult(this.failure);
}
