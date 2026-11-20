# Спецификация требований: refactor_tool (CppMiddleProject8)

Восстановлена по коду ветки `dev`, коммит `8c8c35f` (2025-09-10). Описывает только то, что есть в этом коммите. Обзор проекта — [docs/README.md](docs/README.md).

## 1. Назначение и границы

`refactor_tool` — консольная утилита на Clang LibTooling, которая находит в C++-файле три шаблона кода и правит файл на месте (`src/RefactorTool.cpp`). Проект — практическое задание 8-го спринта курса «Мидл разработчик С++» (`README.md:8`).

В границах:

- утилита `refactor_tool` (`src/RefactorTool.cpp`, `include/RefactorTool.h`);
- сборка CMake (`CMakeLists.txt`, `src/CMakeLists.txt`, `tests/CMakeLists.txt`);
- тесты GoogleTest (`tests/test.cpp`, `tests/main.cpp`) и скрипт проверки `check_refactor.sh` с данными в `tests/tests_data/`;
- окружение разработки: `.devcontainer/`, `.vscode/`.

Вне границ:

- исследование шага 7 (`STEP7_GUIDE.md`): это отчёт о ручных прогонах ASan и `perf`, а не код проекта;
- более поздние коммиты веток `main`, `release`, `test` (`git log --all`) — они здесь не разбирались.

## 2. Контекст

| Участник / система | Роль | Источник |
|---|---|---|
| Разработчик или проверяющий курса | запускает утилиту, тесты и `check_refactor.sh` | `README.md:51`, `check_refactor.sh:11` |
| LLVM/Clang ≥ 19 (в контейнере 20) | библиотеки `clangTooling`, `clangBasic`, `clangASTMatchers`; разбор C++ | `CMakeLists.txt:54-56`, `src/CMakeLists.txt:37`, `.devcontainer/Dockerfile:21-23` |
| GitHub | источник архива GoogleTest на этапе конфигурации CMake | `tests/CMakeLists.txt:17` |
| Файловая система | вход и выход утилиты — один и тот же `.cpp`-файл | `src/RefactorTool.cpp:174-178` |

Среда выполнения: Linux (dev-контейнер на Ubuntu, `.devcontainer/devcontainer.json:2`, `.devcontainer/Dockerfile:1`). Другие платформы в `dev` не описаны.

## 3. Функциональные требования

### Запуск

- **FR-1.** Система должна разбирать командную строку через `CommonOptionsParser` (список исходных файлов, флаги компилятора после `--`) и при ошибке разбора печатать её в stderr и завершаться с кодом 1. Source: `src/RefactorTool.cpp:181-185`. Verification: no test.
- **FR-2.** Система должна прогонять каждый переданный файл через `CodeRefactorAction` в `ClangTool` и возвращать код завершения `ClangTool::run`. Source: `src/RefactorTool.cpp:186-188`. Verification: все три теста `RefactoringTests.*` требуют код 0 (`tests/test.cpp:20-21`).
- **FR-3.** Система должна править только конструкции, расположенные в главном файле единицы трансляции, и не трогать подключённые заголовки. Source: `src/RefactorTool.cpp:57, 87, 108`. Verification: no test.

### Виртуальный деструктор

- **FR-4.** Система должна рассматривать каждый невиртуальный деструктор, объявленный в коде (не неявный). Source: `src/RefactorTool.cpp:130-135`. Verification: `RefactoringTests.AddsVirtualToDestructors` (в т.ч. `~BaseNoDtor() = default`, `tests/tests_data/test1.cpp:6`).
- **FR-5.** Система должна вставлять `virtual ` перед именем деструктора, если в единице трансляции есть класс с определением, производный от класса этого деструктора прямо или через промежуточные классы. Source: `src/RefactorTool.cpp:13-34, 60-75`. Verification: `RefactoringTests.AddsVirtualToDestructors`.
- **FR-6.** Система не должна менять деструктор класса без наследников и уже виртуальный деструктор. Source: `src/RefactorTool.cpp:67-69, 132`. Verification: `RefactoringTests.AddsVirtualToDestructors` (`Standalone`, `BaseVirtual`, `tests/tests_data/test1.cpp:20-30`).
- **FR-7.** Система не должна вставлять `virtual` дважды в одну и ту же позицию начала объявления за один прогон. Source: `src/RefactorTool.cpp:71-76`, `include/RefactorTool.h:33`. Verification: `RefactoringTests.AddsVirtualToDestructors` (`tests/tests_data/test1.cpp:13`, комментарий «Убедимся что один раз virtual»).
- **FR-8.** Система должна выдавать предупреждение `Non-virtual destructor in base class; 'virtual' added` в позиции деструктора. Source: `src/RefactorTool.cpp:78-81`. Verification: no test.

### Пропущенный `override`

- **FR-9.** Система должна находить методы, переопределяющие метод базового класса, у которых нет атрибута `override`, исключая деструкторы. Source: `src/RefactorTool.cpp:137-144`. Verification: `RefactoringTests.AddsOverrideToMethods` (`~Derived()` не меняется, `tests/tests_data/test2.cpp:14`).
- **FR-10.** Система должна вставлять ` override` сразу после закрывающей скобки списка параметров такого метода. Source: `src/RefactorTool.cpp:90-95`. Verification: `RefactoringTests.AddsOverrideToMethods`.
- **FR-11.** Система должна выдавать предупреждение `Method overrides base method but is not marked; 'override' added`. Source: `src/RefactorTool.cpp:96-99`. Verification: no test.

### Копирование в range-for

- **FR-12.** Система должна вставлять `&` после записи типа переменной цикла range-for, если её тип `const`-квалифицирован, не является ссылкой и не является фундаментальным. Source: `src/RefactorTool.cpp:111-121, 146-151`. Verification: `RefactoringTests.AddsReferenceToRangeFor` (`const auto`, явный тип, `decltype(...)::value_type`).
- **FR-13.** Система не должна менять переменные цикла фундаментального типа, ссылочные и не `const`-квалифицированные. Source: `src/RefactorTool.cpp:113`. Verification: `RefactoringTests.AddsReferenceToRangeFor` покрывает фундаментальный тип и `const auto&`; случай без `const` — no test.
- **FR-14.** Система должна выдавать предупреждение `Range-based for uses copying; added '&' reference`. Source: `src/RefactorTool.cpp:122-125`. Verification: no test.

### Запись результата

- **FR-15.** Система должна по окончании обработки файла записывать изменения в тот же файл, а при неудаче записи печатать в stderr `Error applying changes to files.`. Source: `src/RefactorTool.cpp:174-178`. Verification: запись — все три теста `RefactoringTests.*` читают изменённый файл; ветка ошибки — no test.

### Скрипт проверки

- **FR-16.** `check_refactor.sh` должен для `test1.cpp`–`test3.cpp` копировать вход в `tests/tests_data/tmp/temp_<имя>`, запускать `./build/refactor_tool <файл> --`, сравнивать результат с эталоном через `diff -w -B` и печатать итог и различия по каждому файлу. Source: `check_refactor.sh:4-12, 30-71`. Verification: no test.
- **FR-17.** `check_refactor.sh` должен завершаться с кодом 1, если нет `./build/refactor_tool` или каталога `tests/tests_data`. Source: `check_refactor.sh:19-28`. Verification: no test.

### Объявлено, но не реализовано

- Категория опций `refactor-tool options` объявлена, но ни одной опции в ней нет (`src/RefactorTool.cpp:11`).
- Список плагинов clang-tutor (`LACommenter`, `CodeStyleChecker`, `Obfuscator`, `UnusedForLoopVar`, `CodeRefactor`) и цикл их сборки закомментированы (`src/CMakeLists.txt:1-24, 40-73`). Вывод по имени проекта `clang-tutor` (`CMakeLists.txt:2`) и комментариям: каркас сборки взят из clang-tutor.
- `.devcontainer/default` по формату — профиль Conan, но `conanfile` в проекте нет и на файл никто не ссылается.
- `STEP7_GUIDE.md:48` ожидает, что `perf` покажет улучшение после рефакторинга; сравнение по функциям не получено (`STEP7_GUIDE.md:78`).

## 4. Интерфейсы

### Командная строка

| Элемент | Значение | Источник |
|---|---|---|
| `refactor_tool <файлы...> [-- <флаги компилятора>]` | файлы правятся на месте | `src/RefactorTool.cpp:181-188`, `tests/test.cpp:18` |
| опции LibTooling (`-p`, `--extra-arg` и др.) | даёт `CommonOptionsParser`; своих опций нет | `src/RefactorTool.cpp:11, 181` |
| код 1 | ошибка разбора аргументов | `src/RefactorTool.cpp:182-185` |
| иной код | результат `ClangTool::run` | `src/RefactorTool.cpp:188` |

### Диагностика (stderr, уровень warning)

| Сообщение | Правка | Источник |
|---|---|---|
| `Non-virtual destructor in base class; 'virtual' added` | `virtual ` перед деструктором | `src/RefactorTool.cpp:80` |
| `Method overrides base method but is not marked; 'override' added` | ` override` после `)` | `src/RefactorTool.cpp:98` |
| `Range-based for uses copying; added '&' reference` | `&` после типа | `src/RefactorTool.cpp:124` |
| `Error applying changes to files.` | — (ошибка записи) | `src/RefactorTool.cpp:176` |

### `check_refactor.sh`

Запуск из корня проекта без аргументов. Вывод — блок `===== Результаты тестов =====` со строкой на каждый файл (`check_refactor.sh:65-71`).

## 5. Данные

Постоянного хранилища нет. Утилита читает и перезаписывает переданные `.cpp`-файлы (`src/RefactorTool.cpp:174-178`).

| Файл | Назначение | Эталон |
|---|---|---|
| `tests/tests_data/test1.cpp` | деструкторы | `test1_ref.cpp` |
| `tests/tests_data/test2.cpp` | `override` | `test2_ref.cpp` |
| `tests/tests_data/test3.cpp` | range-for | `test3_ref.cpp` |
| `tests/tests_data/for_refactor.cpp` | ручной запуск и отладка (`.vscode/launch.json:12`) | нет |
| `tests/tests_data/leak_example.cpp`, `perf_example.cpp` | примеры шага 7 | нет |

Временные файлы: `temp_test_file.cpp` в рабочем каталоге тестов (`tests/test.cpp:10`), `tests/tests_data/tmp/` у скрипта (`check_refactor.sh:5`).

## 6. Нефункциональные требования

- **NFR-1.** Утилита компилируется по C++17, тесты — по C++23. Source: `CMakeLists.txt:73`, `tests/CMakeLists.txt:4-6`.
- **NFR-2.** Конфигурация прерывается, если LLVM старше 19 или `CT_Clang_INSTALL_DIR` не указывает на установку с `include/llvm` и `lib/cmake/clang/ClangConfig.cmake`. Source: `CMakeLists.txt:29-39, 54-56`.
- **NFR-3.** Код собирается с `-Wall`, с `-fno-rtti`, если LLVM собран без RTTI, и с `-fvisibility-inlines-hidden`, если компилятор его поддерживает. Source: `CMakeLists.txt:82-98`.
- **NFR-4.** Тесты собираются с `-Wfatal-errors` для GCC и Clang. Source: `tests/CMakeLists.txt:8-10`.
- **NFR-5.** Тип сборки по умолчанию — `Debug`; для `src/` он задан жёстко. Source: `CMakeLists.txt:76-79`, `src/CMakeLists.txt:25`.
- **NFR-6.** Окружение разработки воспроизводится dev-контейнером: образ Ubuntu по digest, g++-15, LLVM/Clang 20, gdb, `linux-tools-common`, пользователь `dev`. Source: `.devcontainer/Dockerfile:1-37`, `.devcontainer/devcontainer.json`.

Требований к скорости, объёму входа или памяти в файлах нет.

## 7. Ограничения и зависимости

| Зависимость | Версия | Источник |
|---|---|---|
| CMake | ≥ 3.20 (корень), ≥ 3.30 (`tests/`) | `CMakeLists.txt:1`, `tests/CMakeLists.txt:1` |
| LLVM/Clang (`clangTooling`, `clangBasic`, `clangASTMatchers`) | ≥ 19; в контейнере 20 | `CMakeLists.txt:54`, `src/CMakeLists.txt:37`, `.devcontainer/Dockerfile:21-23` |
| GoogleTest | `release-1.12.1`, архив по URL без контрольной суммы | `tests/CMakeLists.txt:17` |
| g++ | 15 в контейнере | `.devcontainer/Dockerfile:16, 26-27` |

Lock-файлов нет. Сборка требует сети на этапе конфигурации (FetchContent).

## 8. Приёмка

1. В dev-контейнере собрать проект командами из `README.md:36-39`.
2. Из каталога `build/` запустить `./refactor_tool_tests`: должны пройти `AddsVirtualToDestructors`, `AddsOverrideToMethods`, `AddsReferenceToRangeFor` (FR-2, FR-4…FR-7, FR-9, FR-10, FR-12, FR-13, FR-15).
3. Из корня проекта запустить `./check_refactor.sh` и проверить, что все три строки — «пройден» (FR-16). Код возврата скрипта об успехе не говорит (`check_refactor.sh:65-71`).
4. FR-1, FR-3, FR-8, FR-11, FR-14, FR-17 автотестами не покрыты: проверять вручную по stderr и по содержимому заголовков после запуска.

Эти шаги при составлении спецификации не выполнялись.

## 9. Открытые вопросы

- Должна ли реализация из `dev` попасть в основную ветку? Частичный ответ из git: ветка по умолчанию на GitHub — `release` (`git ls-remote --symref origin HEAD`); `main` (до 2026-08-10) и `release`/`test` (до 2026-11-08) отходят от первого коммита `bd7ddbf`, а не от `dev` (`git merge-base`). Коммит с реализацией `8c8c35f` (2025-09-10) есть только в `dev`, в остальных ветках `src/RefactorTool.cpp` — заготовка курса с пометками `todo`.
- Должна ли утилита корректно ставить `override` у методов с `const`, `noexcept`, ref-квалификаторами и trailing return type? Сейчас вставка идёт сразу после `)` (`src/RefactorTool.cpp:93-95`); тестов на эти случаи нет.
- Что ожидается для деструктора, определённого вне класса, и для шаблонов? Защита от повторной вставки есть только для деструкторов (`include/RefactorTool.h:33`); тестов с шаблонами и внешними определениями нет.
- Должен ли `check_refactor.sh` возвращать ненулевой код при проваленном сравнении и удалять `tests/tests_data/tmp`?
- Должны ли тесты работать через `ctest`? Для этого нужны `enable_testing()` (в `dev` его нет нигде) и `WORKING_DIRECTORY` у `gtest_discover_tests` (`tests/CMakeLists.txt:41`). В ветке `main` корень вызывает `enable_testing()`, а CI заканчивается `ctest --preset linux-default` (`.github/workflows/build-and-test.yml:103` в `main`), но код там — заготовка курса.
- Под какой лицензией распространяется код ветки `dev`: файла лицензии в ней нет; в `main` и `release` лежит `LICENSE` (MIT), но коммита `8c8c35f` в этих ветках нет.
- Целевые платформы, кроме Linux-контейнера, и требования к производительности в файлах не указаны.
