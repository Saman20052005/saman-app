import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_ai_app/screens/login/login_controller.dart';
import 'package:health_ai_app/screens/login/widgets/login_form.dart';

void main() {
  group('LoginForm Validation Tests', () {
    test('Register password validation blocks < 8 chars and allows >= 8 chars on client', () {
      expect(LoginForm.validatePassword(null, isLoginMode: false), 'Password is required');
      expect(LoginForm.validatePassword('', isLoginMode: false), 'Password is required');
      expect(LoginForm.validatePassword('12345', isLoginMode: false), 'Min 8 chars');
      expect(LoginForm.validatePassword('123456', isLoginMode: false), 'Min 8 chars');
      expect(LoginForm.validatePassword('secret1', isLoginMode: false), 'Min 8 chars');
      expect(LoginForm.validatePassword('12345678', isLoginMode: false), isNull);
      expect(LoginForm.validatePassword('SecurePassword123!', isLoginMode: false), isNull);
    });

    test('Login password validation checks required and does not block accounts with registration rules', () {
      expect(LoginForm.validatePassword(null, isLoginMode: true), 'Password is required');
      expect(LoginForm.validatePassword('', isLoginMode: true), 'Password is required');
      expect(LoginForm.validatePassword('123', isLoginMode: true), isNull);
      expect(LoginForm.validatePassword('12345', isLoginMode: true), isNull);
      expect(LoginForm.validatePassword('123456', isLoginMode: true), isNull);
      expect(LoginForm.validatePassword('secret1', isLoginMode: true), isNull);
      expect(LoginForm.validatePassword('12345678', isLoginMode: true), isNull);
    });

    test('Email validation checks basic structure and trims whitespace', () {
      expect(LoginForm.validateEmail(null), 'Email is required');
      expect(LoginForm.validateEmail(''), 'Email is required');
      expect(LoginForm.validateEmail('   '), 'Email is required');
      expect(LoginForm.validateEmail('invalid'), 'Invalid email');
      expect(LoginForm.validateEmail('invalid@'), 'Invalid email');
      expect(LoginForm.validateEmail('@domain.com'), 'Invalid email');
      expect(LoginForm.validateEmail('user@domain'), 'Invalid email');
      expect(LoginForm.validateEmail('user@domain.com'), isNull);
      expect(LoginForm.validateEmail('  user@domain.com  '), isNull);
    });

    testWidgets('LoginForm preserves input text and prevents double-submit when loading', (tester) async {
      String? submittedEmail;
      String? submittedPass;
      int submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoginForm(
              isLoginMode: true,
              isLoading: false,
              onSubmit: (email, pass, name, phone) {
                submittedEmail = email;
                submittedPass = pass;
                submitCount++;
              },
              onForgotPassword: () {},
            ),
          ),
        ),
      );

      // Enter email with leading/trailing spaces and password with exact characters
      await tester.enterText(find.byType(TextFormField).at(0), '  athlete@example.com  ');
      await tester.enterText(find.byType(TextFormField).at(1), ' MySecret123 ');
      await tester.pumpAndSettle();

      final loginBtn = find.widgetWithText(ElevatedButton, 'Log In');
      expect(loginBtn, findsOneWidget);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      expect(submitCount, 1);
      expect(submittedEmail, 'athlete@example.com'); // Trimmed
      expect(submittedPass, ' MySecret123 '); // NOT trimmed! Preserves password spaces

      // Now re-render with isLoading: true
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoginForm(
              isLoginMode: true,
              isLoading: true,
              onSubmit: (email, pass, name, phone) {
                submitCount++;
              },
              onForgotPassword: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Submit button is disabled (shows progress indicator)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final disabledButton = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(disabledButton.onPressed, isNull);
    });

    testWidgets('LoginForm in register mode enforces min 8 chars and preserves exact password without trimming', (tester) async {
      String? submittedEmail;
      String? submittedPass;
      String? submittedName;
      String? submittedPhone;
      int submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LoginForm(
                isLoginMode: false,
                isLoading: false,
                onSubmit: (email, pass, name, phone) {
                  submittedEmail = email;
                  submittedPass = pass;
                  submittedName = name;
                  submittedPhone = phone;
                  submitCount++;
                },
                onForgotPassword: () {},
              ),
            ),
          ),
        ),
      );

      // Register fields: 0: Full Name, 1: Phone, 2: Email, 3: Password, 4: Confirm Password
      await tester.enterText(find.byType(TextFormField).at(0), '  Sam Athlete  ');
      await tester.enterText(find.byType(TextFormField).at(1), '  0901234567  ');
      await tester.enterText(find.byType(TextFormField).at(2), '  athlete@example.com  ');
      await tester.enterText(find.byType(TextFormField).at(3), 'secret1'); // 7 chars -> should fail
      await tester.enterText(find.byType(TextFormField).at(4), 'secret1');
      await tester.pumpAndSettle();

      final signUpBtn = find.widgetWithText(ElevatedButton, 'Sign Up');
      expect(signUpBtn, findsOneWidget);
      await tester.tap(signUpBtn);
      await tester.pumpAndSettle();

      // Blocked by min 8 validation
      expect(submitCount, 0);
      expect(find.text('Min 8 chars'), findsOneWidget);

      // Fix password to 8+ chars with whitespace (11 chars total)
      await tester.enterText(find.byType(TextFormField).at(3), ' secret888 ');
      await tester.enterText(find.byType(TextFormField).at(4), ' secret888 ');
      await tester.pumpAndSettle();

      await tester.tap(signUpBtn);
      await tester.pumpAndSettle();

      expect(submitCount, 1);
      expect(submittedName, 'Sam Athlete'); // Trimmed
      expect(submittedPhone, '0901234567'); // Trimmed
      expect(submittedEmail, 'athlete@example.com'); // Trimmed
      expect(submittedPass, ' secret888 '); // NOT trimmed! Exact verbatim password
    });
  });

  group('LoginController Error Extraction Tests', () {
    test('422 Pydantic list error for password maps to friendly message without leaking input', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'password'],
                'msg': 'String should have at least 8 characters',
                'type': 'string_too_short',
                'input': 'secret1',
              }
            ]
          },
        ),
      );

      final msg = LoginController.extractErrorMessage(dioException);
      expect(msg, 'Password must be at least 8 characters.');
      expect(msg.contains('secret1'), isFalse);
    });

    test('422 Pydantic list error for email maps to friendly email message', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'email'],
                'msg': 'value is not a valid email address: There must be something after the @-sign.',
                'type': 'value_error',
              }
            ]
          },
        ),
      );

      final msg = LoginController.extractErrorMessage(dioException);
      expect(msg, 'Please enter a valid email address.');
    });

    test('400 Email already exists string detail maps to clear registered message', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 400,
          data: {'detail': 'Email already exists'},
        ),
      );

      final msg = LoginController.extractErrorMessage(dioException);
      expect(msg, 'This email is already registered. Please log in or use another email.');
    });

    test('400 Social login message preserved without dumping raw payload', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 400,
          data: {
            'detail': 'This email uses Social Login (Google/FB/Apple). Please sign in with that.'
          },
        ),
      );

      final msg = LoginController.extractErrorMessage(dioException);
      expect(msg, 'This email uses Social Login (Google/FB/Apple). Please sign in with that.');
    });

    test('401 Invalid email or password maps to friendly message', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/login'),
          statusCode: 401,
          data: {'detail': 'Invalid email or password'},
        ),
      );

      final msg = LoginController.extractErrorMessage(dioException);
      expect(msg, 'Invalid email or password.');
    });

    test('Timeout and connection errors map to friendly connection messages', () {
      final timeoutException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(
        LoginController.extractErrorMessage(timeoutException),
        'Connection timed out. Please check your internet connection.',
      );

      final connectionException = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        type: DioExceptionType.connectionError,
      );
      expect(
        LoginController.extractErrorMessage(connectionException),
        'Cannot connect to server. Please check your network connection.',
      );
    });

    test('500 Server error maps to server error message', () {
      final serverError = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 500,
          data: 'Internal Server Error',
        ),
      );
      expect(
        LoginController.extractErrorMessage(serverError),
        'Server error occurred. Please try again later.',
      );
    });

    test('Malformed/empty response does not crash and returns safe message', () {
      final emptyResponse = DioException(
        requestOptions: RequestOptions(path: '/api/auth/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/auth/register'),
          statusCode: 422,
          data: null,
        ),
      );
      expect(
        LoginController.extractErrorMessage(emptyResponse),
        'Invalid input format. Please check your email and password.',
      );

      expect(
        LoginController.extractErrorMessage(Exception('unexpected error')),
        'Authentication failed. Please try again.',
      );
    });
  });
}
