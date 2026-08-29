# Шаг 7. Примените инструменты анализа
Оцените эффективность рефакторинга, который вы провели, с помощью инструментов профилирования и динамического анализа Clang LibTooling. Это исследовательская часть, в которой Вы будете работать с двумя примерами: perf_example.cpp (для профилирования производительности) и leak_example.cpp (для анализа утечек памяти).
1. -fsanitize=address
* В файле tests/tests_data/leak_example.cpp базовый класс с наследником имеет невиртуальный деструктор, что приводит к утечке памяти при полиморфном удалении (ресурсы наследника не освобождаются). После добавления virtual утечка устраняется.
* До рефакторинга:
    * Скомпилируйте с AddressSanitizer.
    * Запустите скомпилированную версию программы.
    * Ожидайте отчёт об утечке.
* После рефакторинга повторите действия выше и убедитесь в отсутствии утечек.
```shell
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ g++ -g -fsanitize=address leak_example.cpp -o leak_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ ./leak_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ g++ -g -fsanitize=address leak_example.cpp -o leak_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ ./leak_before
=================================================================
==29988==ERROR: AddressSanitizer: new-delete-type-mismatch on 0x7bb7be820010 in thread T0:
  object passed to delete has wrong type:
  size of the allocated type:   8 bytes;
  size of the deallocated type: 1 bytes.
    #0 0x7f97c01243fb in operator delete(void*, unsigned long) ../../../../src/libsanitizer/asan/asan_new_delete.cpp:155
    #1 0x55a2e237a28c in main /workspaces/CppMiddleProject8/build/leak_example.cpp:18
    #2 0x7f97bf82a577 in __libc_start_call_main ../sysdeps/nptl/libc_start_call_main.h:58
    #3 0x7f97bf82a63a in __libc_start_main_impl ../csu/libc-start.c:360
    #4 0x55a2e237a164 in _start (/workspaces/CppMiddleProject8/build/leak_before+0x1164) (BuildId: e0a18bb73c3a38eb1dd9124fae86c40370ae3ab4)

0x7bb7be820010 is located 0 bytes inside of 8-byte region [0x7bb7be820010,0x7bb7be820018)
allocated by thread T0 here:
    #0 0x7f97c01232db in operator new(unsigned long) ../../../../src/libsanitizer/asan/asan_new_delete.cpp:86
    #1 0x55a2e237a243 in main /workspaces/CppMiddleProject8/build/leak_example.cpp:17
    #2 0x7f97bf82a577 in __libc_start_call_main ../sysdeps/nptl/libc_start_call_main.h:58
    #3 0x7f97bf82a63a in __libc_start_main_impl ../csu/libc-start.c:360
    #4 0x55a2e237a164 in _start (/workspaces/CppMiddleProject8/build/leak_before+0x1164) (BuildId: e0a18bb73c3a38eb1dd9124fae86c40370ae3ab4)

SUMMARY: AddressSanitizer: new-delete-type-mismatch /workspaces/CppMiddleProject8/build/leak_example.cpp:18 in main
==29988==HINT: if you don't care about these errors you may set ASAN_OPTIONS=new_delete_type_mismatch=0
==29988==ABORTING
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ ./refactor_tool leak_example.cpp --
/workspaces/CppMiddleProject8/build/leak_example.cpp:5:5: warning: Невиртуальный деструктор в базовом классе; добавлено 'virtual'
    5 |     ~Base() {}  // Невиртуальный
      |     ^
1 warning generated.
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ g++ -g -fsanitize=address leak_example.cpp -o leak_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ ./leak_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ 
```

2. Используйте perf для анализа производительности
* В файле tests/tests_data/perf_example.cpp есть ненужное копирование в range-for (без &), что приводит к низкой производительности для больших контейнеров. После добавления & копирование устранится, и perf покажет улучшение (меньше CPU времени на копирование).
* До рефакторинга:
    * Скомпилируйте вашу программу.
    * Запустите её под perf.
    * Изучите данные, записанные perf.
    * Сравните данные perf после рефакторинга.
```shell
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ g++ -O2 -g perf_example.cpp -o perf_before                                           
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ perf record -g -F 999 -- ./perf_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ perf report

Samples: 19K of event 'cycles:Pu', Event count (approx.): 1948986277
  Children      Self  Command      Shared Object         Symbol
+   56.80%     0.00%  perf_before  [unknown]             [.] 0000000000000000                                                                   ◆
+   43.08%     0.00%  perf_before  perf_before           [.] 0x00005581d8a193f5                                                                 ▒
+   43.08%     0.00%  perf_before  libc.so.6             [.] __libc_start_main@@GLIBC_2.34                                                      ▒
+   19.05%    18.92%  perf_before  libc.so.6             [.] __memset_avx2_unaligned_erms                                                       ▒
+   13.77%     0.00%  perf_before  perf_before           [.] 0x00005581d8a19334                                                                 ▒
+   13.77%    13.77%  perf_before  perf_before           [.] 0x0000000000001334                                                                 ▒
+    7.95%     0.00%  perf_before  perf_before           [.] 0x00005581d8a1924c                                                                 ▒
+    7.94%     7.94%  perf_before  perf_before           [.] 0x000000000000124c                                                                 ▒
+    7.42%     0.00%  perf_before  perf_before           [.] 0x00005581d8a19254                                                                 ▒
+    7.41%     7.41%  perf_before  perf_before           [.] 0x0000000000001254                                                                 ▒
+    6.17%     0.00%  perf_before  perf_before           [.] 0x00005581d8a19357                                                                 ▒
+    6.17%     6.17%  perf_before  perf_before           [.] 0x0000000000001357                                                                 ▒
+    5.93%     0.00%  perf_before  perf_before           [.] 0x00005581d8a19258                                                                 ▒
+    5.90%     5.90%  perf_before  perf_before           [.] 0x0000000000001258                                                                 ▒
+    4.44%     0.00%  perf_before  perf_before           [.] 0x00005581d8a19330                                                                 ▒
Cannot load tips.txt file, please install perf!

У МЕНЯ НЕ ПОЛУЧИЛОСЬ ВЫВЕСТИ НАЗВАНИЯ ФУНКЦИЙ...
```

```shell
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ ./refactor_tool perf_example.cpp --
/workspaces/CppMiddleProject8/build/perf_example.cpp:10:21: warning: Range-based for использует копирование; добавлена ссылка '&'
   10 |     for (const auto obj : vec) {  // Копирование без &
      |                     ^
1 warning generated.
```

```shell
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ g++ -O2 -g perf_example.cpp -o perf_before                                           
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ perf record -g -F 999 -- ./perf_before
dev@885a79e35681:/workspaces/CppMiddleProject8/build$ perf report
Samples: 1K of event 'cycles:Pu', Event count (approx.): 1607908142
  Children      Self  Command      Shared Object        Symbol
+   47.41%     0.00%  perf_before  [unknown]            [.] 0000000000000000                                                                               ◆
+   35.30%    35.30%  perf_before  perf_before          [.] 0x0000000000001157                                                                             ▒
+   35.30%     0.00%  perf_before  perf_before          [.] 0x000055764505f157                                                                             ▒
+   23.30%     0.00%  perf_before   (deleted)           [.] 0x00007fe16b795b13                                                                             ▒
+   23.17%    23.17%  perf_before   (deleted)           [.] 0x0000000000195b13                                                                             ▒
+    9.73%     0.00%  perf_before  perf_before          [.] 0x000055764505f10c                                                                             ▒
+    9.71%     9.71%  perf_before  perf_before          [.] 0x000000000000110c                                                                             ▒
Cannot load tips.txt file, please install perf!                                       
```