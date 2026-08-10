# cpp-middle-project-sprint-8 <!-- omit in toc -->

- [Начало работы](#начало-работы)
- [Сборка проекта и запуск тестов](#сборка-проекта-и-запуск-тестов)
  - [Команды для сборки проекта](#команды-для-сборки-проекта)
  - [Команды для запуска приложения](#команды-для-запуска-приложения)
- [Сборка под Windows](#сборка-под-windows)

Шаблон репозитория для практического задания 8-го спринта «Мидл разработчик С++»

## Начало работы

1. Нажмите зелёную кнопку `Use this template`, затем `Create a new repository`.
2. Назовите свой репозиторий.
3. Склонируйте созданный репозиторий командой `git clone your-repository-name`.
4. Создайте новую ветку командой `git switch -c development`.
5. Откройте проект в `Visual Studio Code`.
6. Нажмите `F1` и откройте проект в dev-контейнере командой `Dev Containers: Reopen in Container`.

## Сборка проекта и запуск тестов

Данный репозиторий использует три инструмента:

- **cmake** — генератор систем сборки для C и C++. Позволяет создавать проекты, которые могут компилироваться на различных платформах и с различными компиляторами. Подробнее о cmake:
  - https://dzen.ru/a/ZzZGUm-4o0u-IQlb
  - https://neerc.ifmo.ru/wiki/index.php?title=CMake_Tutorial
  - https://cmake.org/cmake/help/book/mastering-cmake/cmake/Help/guide/tutorial/index.html

- **VS Code Dev Docker container** - Docker контейнер, который содержит полностью настроенное окружение для выполнение задания. Подробнее об этой функциональности:
  - https://habr.com/ru/articles/822707/ - "Почти все, что вы хотели бы знать про Docker"
  - https://code.visualstudio.com/docs/devcontainers/containers - официальная документация VS Code
  - https://www.youtube.com/watch?v=p9L7YFqHGk4 - "Docker container for VS Code"
  - https://www.youtube.com/watch?v=pg19Z8LL06w&t=174s&pp=ygUPRG9ja2VyY29udGFpbmVy - "Docker in 1 hour"

### Команды для сборки проекта

- Создайте папку `build`
- Перейдите в нее `cd build`
- Запустите `cmake -DCMAKE_BUILD_TYPE=Debug -DCT_Clang_INSTALL_DIR=/usr/lib/llvm-20/ ../ `
- Запустите `make`

### Команды для запуска приложения

```bash
cd build

./refactor_tool ../tests_data/for_refactor.cpp
```

Для запуска отладки нажмите `F5`, будет произведена сборка и отладка проекта.

Для проверки Ваших изменений так же предусмотрен скрипт `check_refactor.sh`, запустив который, Вы сможете проверить базовые сценарии рафакторинга.

## Сборка под Windows

Dev-контейнер остаётся основным способом сборки, но проект собирается и нативно —
компилятором MSVC, без Docker и без WSL. Точка входа одна: `scripts\build_windows.ps1`.

### Что нужно установить

- **Visual Studio 2022** (Community достаточно) с рабочей нагрузкой
  «Разработка классических приложений на C++». Нужен компилятор MSVC v143;
  проверялось на `cl.exe` 19.44.
- **CMake ≥ 3.21** и **Ninja** на `PATH`. Оба приезжают вместе с компонентом
  Visual Studio «C++ CMake tools for Windows», если ставить их отдельно не хочется.
- **Clang/LLVM 19 или новее — именно в виде дистрибутива для разработки.**
  `CMakeLists.txt` вызывает `find_package(Clang REQUIRED CONFIG)` и линкует
  `clangTooling` / `clangBasic` / `clangASTMatchers`, то есть ему нужны C++-заголовки
  и библиотеки LLVM, а не только `clang.exe`. Привычный установщик
  `LLVM-<версия>-win64.exe` для этого **не подходит**: в нём лежит лишь C API
  (`include\llvm-c`, `libclang.lib`) и нет `lib\cmake\clang\ClangConfig.cmake`.
  Подходит архив с той же страницы релиза:

  ```
  https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz
  ```

  Распакуйте его куда угодно (`tar -xJf <файл>`) и передайте путь ключом
  `-ClangInstallDir` либо задайте переменную окружения `CT_CLANG_INSTALL_DIR`.
  Проверялось на 20.1.8 — той же мажорной версии, что и LLVM в dev-контейнере.
- **GoogleTest ставить не нужно**: его тянет `FetchContent`, поэтому первой сборке
  нужен интернет, а последующим — уже нет.

Отдельно запускать «Developer Command Prompt» не требуется — скрипт сам находит
`vcvars64.bat` (через `vswhere`, с запасными путями) и вносит окружение MSVC в
свой процесс.

### Как собрать

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 `
    -ClangInstallDir C:\llvm\clang+llvm-20.1.8-x86_64-pc-windows-msvc
```

Скрипт конфигурирует CMake, собирает всё, прогоняет `ctest` и в конце печатает
пути к получившимся `.exe`. Результат лежит в `build\windows`: приложение —
`build\windows\refactor_tool.exe`, тесты — `build\windows\refactor_tool_tests.exe`.

```powershell
build\windows\refactor_tool.exe tests\tests_data\for_refactor.cpp --
```

Полезные ключи:

| Ключ | Зачем |
| --- | --- |
| `-BuildType Debug` | сборка с отладочной информацией в `build\windows-debug` |
| `-Clean` | удалить каталог сборки и собрать с нуля |
| `-SkipTests` | не запускать `ctest` |
| `-ClangInstallDir <путь>` | указать дистрибутив Clang/LLVM явно |

### Пресеты CMake

`CMakePresets.json` описывает обе платформы, поэтому IDE (Visual Studio, VS Code,
CLion) подхватывает конфигурацию сама:

| Пресет | Платформа | Генератор | Каталог сборки |
| --- | --- | --- | --- |
| `linux-default` | Linux / dev-контейнер | Unix Makefiles | `build/` |
| `windows-msvc-release` | Windows, MSVC x64 | Ninja | `build/windows/` |
| `windows-msvc-debug` | Windows, MSVC x64 | Ninja | `build/windows-debug/` |

Windows-пресеты рассчитаны на окружение MSVC и берут путь к Clang/LLVM из
переменной `CT_CLANG_INSTALL_DIR`: если запускать их руками, а не через
`scripts\build_windows.ps1`, делать это надо из «Developer PowerShell for VS 2022»
и с заранее выставленной переменной, иначе CMake не найдёт ни `cl.exe`, ни
`ClangConfig.cmake`.

### Что было несовместимо с MSVC

Три места в сборке предполагали GCC/Clang и на Windows ломались; правки сделаны
под `if(MSVC)`, поэтому сборка в dev-контейнере не изменилась:

- `-Wall -fdiagnostics-color=always` и `-fno-rtti` заменены на `/W3 /utf-8` и
  `/GR-`. `/utf-8` тут не косметика: тексты диагностик в `src/RefactorTool.cpp`
  русские, и без этого ключа MSVC читает UTF-8-файлы в системной ANSI-кодировке.
- `check_cxx_compiler_flag(-fvisibility-inlines-hidden ...)` под MSVC не проходит
  и оставляет результат пустым, из-за чего следующий `if(${...} EQUAL "1")`
  становился синтаксической ошибкой CMake ещё до конфигурации. Проверка теперь
  выполняется только не под MSVC.
- `LLVMExports.cmake` из готовой Windows-сборки llvm.org хранит **абсолютный**
  путь к `diaguids.lib` с машины сборщика (там была Visual Studio 2019
  Professional). На чужой машине Ninja падает с «missing and no known rule to
  make it» ещё до компиляции, поэтому CMake подменяет эту запись на DIA SDK
  локальной Visual Studio.

Кроме того, `src/CMakeLists.txt` больше не прибивает `CMAKE_BUILD_TYPE` к `Debug`
для своего подкаталога: готовые библиотеки Clang/LLVM для Windows собраны в
Release против `/MD`, и объект, собранный с `/MDd`, не линкуется с ними
(`LNK2038`). Поэтому же оба Windows-пресета явно просят
`CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL` — отладочная информация в
`windows-msvc-debug` есть, а вот C runtime остаётся release.