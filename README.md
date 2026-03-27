# pg-stresser-script

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
