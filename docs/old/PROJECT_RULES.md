# Project Context & Coding Rules
**Role:** Senior Flutter Engineer.
**Stack:** Flutter, Riverpod (Generator), FastAPI Backend.
**Architecture:** Feature-first Clean Architecture.

## 1. Folder Structure (Feature-first)
Always organize new features using this structure:
lib/features/[feature_name]/
├── data/
│   ├── models/ (extends Entity, Manual JSON mapping)
│   ├── repositories/ (implements Domain Repository)
│   └── datasources/ (Remote/Local data sources)
├── domain/
│   ├── entities/ (extends Equatable)
│   ├── repositories/ (Abstract Interface)
│   └── usecases/ (Single responsibility)
└── presentation/
    ├── controllers/ (Riverpod @riverpod generated)
    ├── screens/
    └── widgets/

## 2. Critical Coding Rules
### A. State Management (Riverpod)
* **MUST USE:** `riverpod_generator` syntax (`@riverpod`).
* **FORBIDDEN:** Do NOT use `StateNotifier` or `ChangeNotifier`.
* **Controller:** Class must extend `_$ClassName`. Return `FutureOr<T>` for async data.
* **Error Handling:** Use `state = await AsyncValue.guard(() => ...)` in methods.
* **Ref:** Follow `DailyNutritionController` pattern.

### B. Data & Domain Layer
* **Entity:** Must extend `Equatable`. Use `enum` for types.
* **Model:** Must extend `Entity`. Implement `fromJson` manually (NO freezed for models).
* **Repository Interface:** Return `Future<T>` directly. Do NOT return `Either`. Throw exceptions on failure.

### C. Naming Conventions
* **Dart:** `camelCase` (variables, functions).
* **Files:** `snake_case.dart`.
* **JSON:** `snake_case` (from FastAPI).

---

## 3. Code Blueprints (COPY THESE PATTERNS)

### Blueprint: Controller (Riverpod Generator)
```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'my_controller.g.dart';

@riverpod
class MyController extends _$MyController {
  @override
  FutureOr<MyEntity> build() async {
    return _fetchData();
  }

  Future<MyEntity> _fetchData() async {
    // Call UseCase or Repository
    return ref.read(myUseCaseProvider).execute();
  }

  Future<void> performAction() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(myRepositoryProvider).doSomething();
      return _fetchData(); // Reload data
    });
  }
}

## 4. Language Protocol (VIETNAMESE MODE)
**IMPORTANT:** The user will prompt in **VIETNAMESE**. You must act as a Vietnamese-speaking Senior Colleague.

### A. Interpretation Rules
When the user asks in Vietnamese, map their words to these technical concepts:
* "Tạo", "Viết", "Sinh code" -> **Generate** (Follow Blueprints above).
* "Controller", "Logic", "Xử lý" -> **Riverpod Controller** (`@riverpod`).
* "Model", "Dữ liệu" -> **Data Model** (Manual `fromJson`).
* "Lỗi", "Bug" -> **AsyncValue.guard** or Error Handling.

### B. Output Rules
1.  **Code:** Must use **ENGLISH** for variable names, functions, and comments (Standard naming convention).
2.  **Explanation:** Explain your solution in **VIETNAMESE**.
3.  **Tone:** Professional, concise, helpful.