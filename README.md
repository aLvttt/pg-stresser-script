# pg-stresser-script

This README is bilingual: the Russian version comes first, and the full English version is located at the end of the file.
Этот README двуязычный: сначала идёт русская версия, а полный английский дубль находится в конце файла.

`pg-stresser.sh` — это bash-скрипт для PostgreSQL, который умеет:

- подготовить тестовую зону в базе;
- выдать контролируемое количество SQL-запросов;
- удалить созданную тестовую зону.

Если говорить совсем просто: это инструмент, который помогает намеренно и предсказуемо "постучаться" в PostgreSQL нужным числом запросов, чтобы проверить, как это увидит ваш агент, аудит или другая система наблюдения.

## Минимальная шпаргалка

Если вам вообще не хочется читать всё ниже, то вот суть:

1. Самый простой старт — просто запустите `./pg-stresser.sh`: откроется wizard с пошаговыми вопросами.
2. Хотите, чтобы скрипт сам всё создал — используйте `--db-source auto`.
3. Хотите использовать свою БД — используйте `--db-source existing`.
4. Сначала обычно идёт `prepare`, потом `run`, потом при необходимости `delete`.
5. Для быстрого старта почти всегда хватает `--preset smoke` или `--preset balanced`.
6. Скрипт не создаёт файлов на диске.
7. Скрипт работает через Unix socket, а не через `localhost`.

## Что делает скрипт

Скрипт умеет работать в трёх режимах:

- `prepare` — создать или пересоздать тестовую зону;
- `run` — выполнить нагрузочный прогон;
- `delete` — удалить тестовую зону.

Во время нагрузки скрипт:

- открывает один постоянный `psql`-сеанс;
- отправляет SQL-запросы в заданном темпе;
- считает, сколько запросов было успешно выполнено;
- считает, сколько запросов завершились ошибкой;
- печатает финальную сводку.

Важно: одна операция в текущей версии скрипта всегда означает один SQL-запрос.

## Что скрипт не делает

- Не создаёт файлов на файловой системе.
- Не пишет отчёты в `.txt`, `.log`, `.csv` и так далее.
- Не запускает параллельный пул соединений.
- Не работает по TCP-хостам вроде `127.0.0.1` или `localhost`.

Скрипт требует Unix socket path в `--host`, например:

```bash
/var/run/postgresql
```

## Что скрипт создаёт в PostgreSQL

Если вы используете режим `--db-source auto`, скрипт может создать:

- отдельную роль;
- отдельную базу;
- схему;
- таблицу;
- индексы;
- тестовые строки.

Если вы используете режим `--db-source existing`, скрипт не создаёт отдельную роль и базу, но создаёт или пересоздаёт таблицу в уже существующей БД.

## Значения по умолчанию

Если вы ничего не задаёте вручную, используются такие значения:

| Параметр | Значение |
|---|---|
| `PGHOST` | `/var/run/postgresql` |
| `PGPORT` | `5432` |
| `PGDATABASE` | `stresser_test` |
| `PGUSER` | `stresser_user` |
| `PGPASSWORD` | `stresser_pass` |
| `TEST_SCHEMA` | `stresser_probe` |
| `TEST_TABLE` | `sql_events` |
| `RPM` | `10000` |
| `DURATION` | `60` |
| `INITIAL_ROWS` | `200` |
| `PAYLOAD_SIZE` | `64` |
| `REPORT_EVERY` | `5` |

Административное подключение по умолчанию:

| Параметр | Значение |
|---|---|
| `PGADMIN_HOST` | такой же, как `PGHOST` |
| `PGADMIN_PORT` | такой же, как `PGPORT` |
| `PGADMIN_DATABASE` | `postgres` |
| `PGADMIN_USER` | `postgres` |
| `PGADMIN_PASSWORD` | пусто |

## Требования

На машине должны быть доступны:

- `bash`
- `psql`
- `awk`
- `sort`
- `date`
- `wc`
- `tr`
- `grep`
- `head`
- `tail`
- `sleep`

На практике обычно достаточно Linux с установленным PostgreSQL client package.

## Самый простой старт

### Вариант 1. Просто запустить мастер

```bash
./pg-stresser.sh
```

Если скрипт запущен в интерактивном терминале без аргументов, он сам откроет пошаговый wizard.

То же самое можно вызвать явно:

```bash
./pg-stresser.sh --interactive
```

### Вариант 2. Автоматически создать тестовую зону

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
```

Что произойдёт:

- скрипт подключится как администратор;
- создаст отдельную тестовую БД и роль;
- создаст схему и таблицу;
- заполнит таблицу начальными данными.

### Вариант 3. Запустить нагрузку по готовой тестовой зоне

```bash
./pg-stresser.sh --mode run --preset smoke
```

Этот короткий вариант подходит только если тестовая зона уже подготовлена и параметры подключения совпадают с дефолтами скрипта или заранее заданы через переменные окружения.

### Вариант 4. Удалить авто-созданную тестовую зону

```bash
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

## Как работать правильно

У скрипта есть два основных сценария.

### Сценарий A. `auto`

Используйте `--db-source auto`, если хотите, чтобы скрипт сам подготовил отдельную тестовую зону.

Это удобно, когда:

- вы не хотите вручную создавать БД и пользователя;
- вы хотите изолированную тестовую среду;
- вы хотите потом легко удалить всё одной командой.

Типичный порядок действий:

1. Подготовить тестовую зону.
2. Запустить нагрузку.
3. При необходимости удалить тестовую зону.

Если хотите самый предсказуемый путь без сюрпризов, используйте именно этот сценарий.

Пример:

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
./pg-stresser.sh --mode run --db-source auto --host /var/run/postgresql --port 5432 --database stresser_test --user stresser_user --password stresser_pass --schema stresser_probe --table sql_events --preset smoke
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

Почему здесь команда `run` длинная:

- так нагляднее видно, в какую именно БД и под каким пользователем идёт нагрузка;
- это безопаснее для понимания, чем надеяться на значения по умолчанию;
- такой формат проще копировать в документацию и в тестовые инструкции.

### Сценарий B. `existing`

Используйте `--db-source existing`, если у вас уже есть нужная БД и учётные данные.

Это удобно, когда:

- роль и база уже созданы заранее;
- вам нельзя создавать отдельную БД;
- вы хотите работать в уже существующем окружении.

Пример:

```bash
./pg-stresser.sh --mode prepare --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --preset balanced
./pg-stresser.sh --mode delete --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
```

## Важное предупреждение про `prepare`

Режим `prepare` не "аккуратно подготавливает", а именно пересоздаёт тестовую зону.

Что это означает:

- в `auto`-режиме он может удалить и заново создать тестовую БД и тестовую роль;
- в `existing`-режиме он удаляет целевую таблицу и создаёт её заново;
- все данные в тестовой таблице будут потеряны.

Если вы не уверены, что делаете это в безопасной тестовой среде, сначала остановитесь и проверьте параметры.

## Как устроена нагрузка

Скрипт генерирует четыре типа SQL-операций:

- `select`
- `insert`
- `update`
- `delete`

По умолчанию используется смешанный профиль с весами:

- `select=60`
- `insert=25`
- `update=10`
- `delete=5`

То есть запросы распределяются не поровну, а случайно с этими весами.

Если нужна только одна операция, используйте `--only`.

Пример только `SELECT`:

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 600 --duration 60 --only select
```

Пример только `INSERT`:

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 600 --duration 60 --only insert
```

Пример смешанного режима:

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 1200 --duration 60 --select-weight 70 --insert-weight 20 --update-weight 5 --delete-weight 5
```

## Preset-профили

Скрипт поддерживает готовые пресеты.

### `smoke`

Подходит для быстрой проверки "вообще работает или нет".

- `120 SQL/min`
- `60 sec`
- `50` seed rows
- payload size `32`

### `balanced`

Основной сбалансированный профиль по умолчанию.

- `600 SQL/min`
- `60 sec`
- `200` seed rows
- payload size `64`

### `high`

Более тяжёлый прогон.

- `5000 SQL/min`
- `60 sec`
- `1000` seed rows
- payload size `128`

Пример:

```bash
./pg-stresser.sh --mode run --preset balanced
```

## Самые полезные аргументы

| Аргумент | Что означает |
|---|---|
| `--mode prepare` | подготовить тестовую зону |
| `--mode run` | выполнить нагрузку |
| `--mode delete` | удалить тестовую зону |
| `--db-source auto` | скрипт сам создаёт тестовую БД и роль |
| `--db-source existing` | использовать уже существующую БД |
| `--host` | путь к Unix socket директории PostgreSQL |
| `--port` | порт PostgreSQL |
| `--database` | имя БД для нагрузки |
| `--user` | пользователь для нагрузки |
| `--password` | пароль пользователя для нагрузки |
| `--schema` | схема |
| `--table` | таблица |
| `--admin-host` | Unix socket директория для админ-подключения |
| `--admin-port` | админ-порт |
| `--admin-db` | админ-БД |
| `--admin-user` | админ-пользователь |
| `--admin-password` | админ-пароль |
| `--rpm` | сколько SQL в минуту нужно выдать |
| `--duration` | сколько секунд должен идти прогон |
| `--initial-rows` | сколько начальных строк засеять в таблицу |
| `--payload-size` | размер текстовой нагрузки в `payload` |
| `--tag` | собственная метка прогона |
| `--only` | ограничить операции, например `select,insert` |
| `--report-every` | как часто печатать прогресс |

## Переменные окружения

Вместо CLI-аргументов можно использовать переменные окружения:

```bash
export PGHOST=/var/run/postgresql
export PGPORT=5432
export PGDATABASE=stresser_test
export PGUSER=stresser_user
export PGPASSWORD=stresser_pass

export TEST_SCHEMA=stresser_probe
export TEST_TABLE=sql_events

export PGADMIN_HOST=/var/run/postgresql
export PGADMIN_PORT=5432
export PGADMIN_DATABASE=postgres
export PGADMIN_USER=postgres
export PGADMIN_PASSWORD=secret
```

После этого можно запускать короче:

```bash
./pg-stresser.sh --mode prepare --db-source auto
./pg-stresser.sh --mode run --preset smoke
```

Если используете переменные окружения, убедитесь, что они действительно экспортированы в текущую shell-сессию, иначе скрипт возьмёт свои значения по умолчанию.

## Что будет в таблице

При `prepare` создаётся таблица примерно такого смысла:

- `id`
- `event_name`
- `category`
- `payload`
- `amount`
- `created_at`
- `updated_at`

После создания таблица заполняется начальными строками через `generate_series`.

## Как считать итоговый вывод

В конце скрипт печатает итоговую сводку.

### `Run window`

- `Script start / Script end` — когда начался и закончился весь скрипт целиком.
- `Script elapsed` — полное время жизни процесса.
- `Load start / Load end` — время начала и конца именно нагрузочного окна.
- `Wall time` — сколько реально длился прогон нагрузки.
- `Window (target)` — сколько секунд вы просили через `--duration`.

### `Execution summary`

- `Target table` — таблица, куда шли запросы.
- `Run tag` — уникальная метка прогона.
- `Submitted` — сколько операций скрипт попытался отправить.
- `Completed` — сколько операций дошло до финального результата.
- `Lost (gen)` — сколько операций потерялось на уровне генератора.
- `Successful` — сколько SQL завершилось успешно.
- `Errors` — сколько SQL завершилось ошибкой.
- `Actual SQL/min (by target window)` — сколько успешных SQL в минуту получилось по отношению к целевому окну времени.

Если вам нужна одна короткая логика чтения:

- `Errors=0` хорошо;
- `Lost=0` хорошо;
- `Successful` близко к `Submitted` хорошо;
- `Wall time` сильно больше `Window (target)` значит база не успевала за заданным темпом.

## Как понять, сколько SQL реально будет отправлено

Скрипт заранее считает планируемое число операций по формуле:

```text
RPM * DURATION / 60
```

Примеры:

- `120 RPM` на `60 sec` = `120` SQL
- `600 RPM` на `60 sec` = `600` SQL
- `1200 RPM` на `30 sec` = `600` SQL

Поскольку в текущей версии одна операция = один SQL, это и есть ориентир по количеству запросов.

## Ограничения, о которых лучше знать заранее

### 1. Только локальный Unix socket

Скрипт не примет:

```bash
--host 127.0.0.1
```

или

```bash
--host localhost
```

Нужен именно путь вида:

```bash
--host /var/run/postgresql
```

### 2. В `auto`-режиме админ и техпользователь должны быть разными

Нельзя, чтобы:

- `--admin-user` совпадал с `--user`
- `--admin-db` совпадала с `--database`

Это защита от случайного разрушения рабочей БД.

### 3. Имена PostgreSQL-объектов должны быть "простыми"

Скрипт ожидает идентификаторы вроде:

```text
stresser_test
stresser_user
stresser_probe
sql_events
```

Он не рассчитан на экзотические имена с пробелами, дефисами и сложным quoting.

### 4. Пароль в CLI может светиться в истории команд

Вот так работать можно:

```bash
./pg-stresser.sh --password secret
```

Но это может быть видно в shell history или списке процессов.

Безопаснее использовать переменные окружения или интерактивный мастер.

## Частые сценарии

### Быстро проверить, что всё вообще живое

```bash
./pg-stresser.sh --mode run --preset smoke
```

### Дать ровно средний тестовый поток

```bash
./pg-stresser.sh --mode run --preset balanced
```

### Дать интенсивный поток

```bash
./pg-stresser.sh --mode run --preset high
```

### Дать только чтение

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only select
```

### Дать только запись

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only insert
```

### Дать смесь только `SELECT` и `INSERT`

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only select,insert
```

## Примеры полного цикла

### Полный цикл в `auto`

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
./pg-stresser.sh --mode run --db-source auto --host /var/run/postgresql --port 5432 --database stresser_test --user stresser_user --password stresser_pass --schema stresser_probe --table sql_events --preset balanced
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

### Полный цикл в `existing`

```bash
./pg-stresser.sh --mode prepare --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 1000 --duration 60 --only select,insert
./pg-stresser.sh --mode delete --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
```

## Если что-то сломалось

Вот самые частые причины проблем:

- `missing command: psql` — не установлен PostgreSQL client.
- `PostgreSQL connection must use a local socket directory` — в `--host` передан не путь, а TCP-адрес.
- `admin connection failed` — неверные админ-параметры.
- `cannot connect using the provided existing DB credentials` — неверные параметры пользовательского подключения.
- ошибка про зарезервированные имена ролей с `pg_` — нельзя создавать пользовательские роли с префиксом `pg_`.

---

# English Version

`pg-stresser.sh` is a bash script for PostgreSQL that can:

- prepare a test zone in the database;
- generate a controlled number of SQL queries;
- delete the created test zone.

Put simply, this tool lets you "knock on PostgreSQL" in a deliberate and predictable way with a known number of queries, so you can verify how your agent, audit system, or any other monitoring system sees that traffic.

## Quick Cheat Sheet

If you do not want to read the full document, here is the short version:

1. The easiest start is to run `./pg-stresser.sh`: it will open an interactive wizard with step-by-step questions.
2. If you want the script to create everything for you, use `--db-source auto`.
3. If you want to use your own existing database, use `--db-source existing`.
4. The usual flow is `prepare`, then `run`, then `delete` if needed.
5. For a quick start, `--preset smoke` or `--preset balanced` is usually enough.
6. The script does not create files on disk.
7. The script works through a Unix socket, not through `localhost`.

## What The Script Does

The script works in three modes:

- `prepare` — create or recreate a test zone;
- `run` — execute a load run;
- `delete` — delete the test zone.

During the load run, the script:

- opens one persistent `psql` session;
- sends SQL queries at a configured rate;
- counts successful queries;
- counts failed queries;
- prints a final summary.

Important: in the current version, one operation always means one SQL query.

## What The Script Does Not Do

- It does not create files on the filesystem.
- It does not write reports into `.txt`, `.log`, `.csv`, and so on.
- It does not run a parallel connection pool.
- It does not work with TCP hosts such as `127.0.0.1` or `localhost`.

The script requires a Unix socket path in `--host`, for example:

```bash
/var/run/postgresql
```

## What The Script Creates In PostgreSQL

If you use `--db-source auto`, the script may create:

- a dedicated role;
- a dedicated database;
- a schema;
- a table;
- indexes;
- seed rows.

If you use `--db-source existing`, the script does not create a separate role or database, but it does create or recreate the target table inside an existing database.

## Default Values

If you do not override anything manually, these values are used:

| Parameter | Value |
|---|---|
| `PGHOST` | `/var/run/postgresql` |
| `PGPORT` | `5432` |
| `PGDATABASE` | `stresser_test` |
| `PGUSER` | `stresser_user` |
| `PGPASSWORD` | `stresser_pass` |
| `TEST_SCHEMA` | `stresser_probe` |
| `TEST_TABLE` | `sql_events` |
| `RPM` | `10000` |
| `DURATION` | `60` |
| `INITIAL_ROWS` | `200` |
| `PAYLOAD_SIZE` | `64` |
| `REPORT_EVERY` | `5` |

Default administrative connection values:

| Parameter | Value |
|---|---|
| `PGADMIN_HOST` | same as `PGHOST` |
| `PGADMIN_PORT` | same as `PGPORT` |
| `PGADMIN_DATABASE` | `postgres` |
| `PGADMIN_USER` | `postgres` |
| `PGADMIN_PASSWORD` | empty |

## Requirements

The following commands must be available on the machine:

- `bash`
- `psql`
- `awk`
- `sort`
- `date`
- `wc`
- `tr`
- `grep`
- `head`
- `tail`
- `sleep`

In practice, Linux with the PostgreSQL client package installed is usually enough.

## The Simplest Start

### Option 1. Just Run The Wizard

```bash
./pg-stresser.sh
```

If the script is started in an interactive terminal without arguments, it automatically opens the step-by-step wizard.

You can also start it explicitly:

```bash
./pg-stresser.sh --interactive
```

### Option 2. Automatically Create A Test Zone

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
```

What happens:

- the script connects as an administrator;
- creates a dedicated test database and role;
- creates the schema and table;
- fills the table with initial data.

### Option 3. Run Load Against An Existing Test Zone

```bash
./pg-stresser.sh --mode run --preset smoke
```

This short form only works if the test zone is already prepared and the connection parameters match the script defaults or are already provided through environment variables.

### Option 4. Delete The Auto-Created Test Zone

```bash
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

## Recommended Ways To Work

The script has two main scenarios.

### Scenario A. `auto`

Use `--db-source auto` if you want the script to prepare a separate test zone by itself.

This is convenient when:

- you do not want to create a database and user manually;
- you want an isolated test environment;
- you want to remove everything easily with one command later.

Typical order of actions:

1. Prepare the test zone.
2. Run the load.
3. Delete the test zone if needed.

If you want the most predictable path with the fewest surprises, use this scenario.

Example:

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
./pg-stresser.sh --mode run --db-source auto --host /var/run/postgresql --port 5432 --database stresser_test --user stresser_user --password stresser_pass --schema stresser_probe --table sql_events --preset smoke
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

Why the `run` command is long here:

- it makes it obvious which database and user are used;
- it is easier to understand than relying on hidden defaults;
- this form is easier to copy into documentation and test instructions.

### Scenario B. `existing`

Use `--db-source existing` if you already have a suitable database and credentials.

This is convenient when:

- the role and database already exist;
- you are not allowed to create a separate database;
- you want to work in an existing environment.

Example:

```bash
./pg-stresser.sh --mode prepare --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --preset balanced
./pg-stresser.sh --mode delete --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
```

## Important Warning About `prepare`

`prepare` does not gently "set things up". It recreates the test zone.

That means:

- in `auto` mode it may drop and recreate the test database and test role;
- in `existing` mode it drops the target table and creates it again;
- all data in the test table will be lost.

If you are not sure that you are working in a safe test environment, stop and verify the parameters first.

## How Load Generation Works

The script generates four types of SQL operations:

- `select`
- `insert`
- `update`
- `delete`

By default, it uses a mixed profile with these weights:

- `select=60`
- `insert=25`
- `update=10`
- `delete=5`

In other words, the queries are not distributed evenly. They are chosen randomly according to those weights.

If you need only one operation type, use `--only`.

Example: only `SELECT`

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 600 --duration 60 --only select
```

Example: only `INSERT`

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 600 --duration 60 --only insert
```

Example: mixed mode

```bash
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 1200 --duration 60 --select-weight 70 --insert-weight 20 --update-weight 5 --delete-weight 5
```

## Preset Profiles

The script supports ready-made presets.

### `smoke`

Good for a quick "does it work at all?" check.

- `120 SQL/min`
- `60 sec`
- `50` seed rows
- payload size `32`

### `balanced`

The main balanced default profile.

- `600 SQL/min`
- `60 sec`
- `200` seed rows
- payload size `64`

### `high`

A heavier run.

- `5000 SQL/min`
- `60 sec`
- `1000` seed rows
- payload size `128`

Example:

```bash
./pg-stresser.sh --mode run --preset balanced
```

## Most Useful Arguments

| Argument | Meaning |
|---|---|
| `--mode prepare` | prepare the test zone |
| `--mode run` | execute a load run |
| `--mode delete` | delete the test zone |
| `--db-source auto` | let the script create a dedicated test DB and role |
| `--db-source existing` | use an existing database |
| `--host` | path to the PostgreSQL Unix socket directory |
| `--port` | PostgreSQL port |
| `--database` | database name for the workload |
| `--user` | workload user |
| `--password` | workload user password |
| `--schema` | schema |
| `--table` | table |
| `--admin-host` | Unix socket directory for the admin connection |
| `--admin-port` | admin port |
| `--admin-db` | admin database |
| `--admin-user` | admin user |
| `--admin-password` | admin password |
| `--rpm` | target SQL statements per minute |
| `--duration` | load duration in seconds |
| `--initial-rows` | how many initial rows to seed |
| `--payload-size` | payload text size |
| `--tag` | custom run tag |
| `--only` | restrict operations, for example `select,insert` |
| `--report-every` | how often to print progress |

## Environment Variables

Instead of CLI arguments, you can use environment variables:

```bash
export PGHOST=/var/run/postgresql
export PGPORT=5432
export PGDATABASE=stresser_test
export PGUSER=stresser_user
export PGPASSWORD=stresser_pass

export TEST_SCHEMA=stresser_probe
export TEST_TABLE=sql_events

export PGADMIN_HOST=/var/run/postgresql
export PGADMIN_PORT=5432
export PGADMIN_DATABASE=postgres
export PGADMIN_USER=postgres
export PGADMIN_PASSWORD=secret
```

After that, you can use shorter commands:

```bash
./pg-stresser.sh --mode prepare --db-source auto
./pg-stresser.sh --mode run --preset smoke
```

If you use environment variables, make sure they are really exported in the current shell session. Otherwise the script will fall back to its built-in defaults.

## What Will Be In The Table

During `prepare`, the script creates a table with fields conceptually like these:

- `id`
- `event_name`
- `category`
- `payload`
- `amount`
- `created_at`
- `updated_at`

After the table is created, it is filled with initial rows using `generate_series`.

## How To Read The Final Output

At the end, the script prints a final summary.

### `Run window`

- `Script start / Script end` — when the whole script started and finished.
- `Script elapsed` — total process lifetime.
- `Load start / Load end` — start and end time of the actual load window.
- `Wall time` — how long the load run really lasted.
- `Window (target)` — how many seconds you requested with `--duration`.

### `Execution summary`

- `Target table` — the table that received the queries.
- `Run tag` — a unique run marker.
- `Submitted` — how many operations the script attempted to send.
- `Completed` — how many operations reached a final result.
- `Lost (gen)` — how many operations were lost on the generator side.
- `Successful` — how many SQL operations completed successfully.
- `Errors` — how many SQL operations failed.
- `Actual SQL/min (by target window)` — how many successful SQL operations per minute were achieved relative to the target time window.

If you want one short rule of thumb:

- `Errors=0` is good;
- `Lost=0` is good;
- `Successful` close to `Submitted` is good;
- if `Wall time` is much larger than `Window (target)`, the database was not keeping up with the requested rate.

## How To Estimate The Real SQL Count

The script computes the planned number of operations using this formula:

```text
RPM * DURATION / 60
```

Examples:

- `120 RPM` for `60 sec` = `120` SQL
- `600 RPM` for `60 sec` = `600` SQL
- `1200 RPM` for `30 sec` = `600` SQL

Because in the current version one operation equals one SQL statement, this is also the main estimate for the real number of queries.

## Limitations You Should Know In Advance

### 1. Only Local Unix Socket

The script will not accept:

```bash
--host 127.0.0.1
```

or:

```bash
--host localhost
```

You must use a path like:

```bash
--host /var/run/postgresql
```

### 2. In `auto` Mode, The Admin And Technical User Must Be Different

The following must not be the same:

- `--admin-user` and `--user`
- `--admin-db` and `--database`

This is a safeguard against accidentally destroying the wrong database.

### 3. PostgreSQL Object Names Must Be "Simple"

The script expects identifiers like:

```text
stresser_test
stresser_user
stresser_probe
sql_events
```

It is not designed for exotic names with spaces, dashes, or heavy quoting.

### 4. Passwords Passed In CLI May Be Visible In Shell History

This works:

```bash
./pg-stresser.sh --password secret
```

But it may be visible in shell history or in the process list.

Using environment variables or the interactive wizard is safer.

## Common Scenarios

### Quickly Check That Everything Is Alive

```bash
./pg-stresser.sh --mode run --preset smoke
```

### Generate A Medium Test Flow

```bash
./pg-stresser.sh --mode run --preset balanced
```

### Generate A Heavy Flow

```bash
./pg-stresser.sh --mode run --preset high
```

### Generate Read-Only Traffic

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only select
```

### Generate Write-Only Traffic

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only insert
```

### Generate Only `SELECT` And `INSERT`

```bash
./pg-stresser.sh --mode run --rpm 600 --duration 60 --only select,insert
```

## Full Workflow Examples

### Full Workflow In `auto`

```bash
./pg-stresser.sh --mode prepare --db-source auto --admin-password secret
./pg-stresser.sh --mode run --db-source auto --host /var/run/postgresql --port 5432 --database stresser_test --user stresser_user --password stresser_pass --schema stresser_probe --table sql_events --preset balanced
./pg-stresser.sh --mode delete --db-source auto --admin-password secret
```

### Full Workflow In `existing`

```bash
./pg-stresser.sh --mode prepare --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
./pg-stresser.sh --mode run --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events --rpm 1000 --duration 60 --only select,insert
./pg-stresser.sh --mode delete --db-source existing --host /var/run/postgresql --port 5432 --database mydb --user myuser --password secret --schema stresser_probe --table sql_events
```

## If Something Breaks

Here are the most common causes of problems:

- `missing command: psql` — the PostgreSQL client is not installed.
- `PostgreSQL connection must use a local socket directory` — `--host` contains a TCP address instead of a Unix socket path.
- `admin connection failed` — wrong admin connection parameters.
- `cannot connect using the provided existing DB credentials` — wrong workload connection parameters.
- an error about reserved role names with `pg_` — user-created roles must not start with the `pg_` prefix.
