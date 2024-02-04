# Домашнее задание #2

## Задача

1. [Подготовить виртуальные машины](#createvm)
2. [Установка, настройка postgresql и прикладного ПО](#install)
3. [Установка pgbouncer и настройка](#pgbouncer)
4. [Установка альтернативного пулера и настройка](#odyssey)
5. [Провести extended бенчмарки c 500+ подключений](#benchmarks)


## Решение

## 1. Подготовить виртуальные машины <a name="createvm"></a>

### 1.1 Окружение: 

Виртуальные машины `Proxmox` на домашнем сервере:

Proxmox Server:
```
Intel(R) Xeon(R) CPU E5-2699 v3 @ 2.30GHz
DDR4 Synchronous 2133 MHz
m.2 NVME KINGSTON SNVS1000G
```

Ресурсы/параметры виртуальных машин:
```
pvm_disks:
    - name: scsi0
      size: 40
      iothread: true
      ssd : true

pvm_memory: 16384
pvm_cores: 8
```

### 1.2 Создание ВМ: 

Плейбук:

```
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts playbooks/1_pvecreate.yml -v
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts playbooks/1_pvecreate.yml -v -t start
```

## 2. Установка, настройка postgresql и прикладного ПО <a name="install"></a>

### 2.1 Установка дополнительных утилит и обновление базовых пакетов

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/2_install_common.yml
```

### 2.2 Установка postgres

- установка официального репозитория
- установка необходимых пакетов и прикладного ПО

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/5_install_pgsql.yml
```

### 2.3 Бэкап дефолтного и обновление конфигов postgresql

- бэкап дефолтного конфига
- обновления конфигов от cybertec
- исправление hba

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/6_config_pgsql.yml
```

### 2.4 Подготовка рабочих нагрузок для тестов

Значения:
```
workload_db_size: medium
workload_db_file: "{{ workload_db_name }}_{{ workload_db_size }}.tar.gz"
workload_files_dir: "{{ lookup('ansible.builtin.env', 'PWD') }}"
workload_file_url: "https://storage.googleapis.com/thaibus/{{ workload_db_file }}"
workload_db_name: thai
workload_force: false
```

- Cкачивание и загрузка дампа в тестовую БД
- Вакууминг после загрузки опционально

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/7_prepare_workload.yml
```


## 3. Установка pgbouncer и настройка <a name="pgbouncer"></a>

### 3.1 Установка паролей для пользователей:

- Создание пароля для postgres и дополнительного пользователя
```
postgresql_users:
 - name: postgres
   password: "{{ postgres_password }}"
 - name: admindb 
   password: "{{ admindb_password }}"
```
```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/10_postgres_users.yml
```

### 3.2 Установка и настройка pgbouncer

- установка pgbouncer
- настройка дополнительная
- возможность установки нескольких инстансов используя so_reuse_port
- генерация userlist.txt хешей паролей 

Темплейт конфига pgbouncer`:

```ini
[databases]

thai = host=127.0.0.1 port=5432 dbname=thai

[pgbouncer]

logfile = /var/log/postgresql/{{ item }}.log

pidfile = /var/run/postgresql/{{ item }}.pid

unix_socket_dir = /var/run/postgresql/{{ item }}_sock

listen_addr = *

listen_port = 6432

auth_type = scram-sha-256

auth_file = /etc/pgbouncer/userlist.txt

admin_users = admindb

so_reuseport = 1

pool_mode = {{ pgbouncer_pool_mode | default('session') }}

max_client_conn = {{ pgbouncer_max_client_conn | default(100) }}

default_pool_size = {{ pgbouncer_default_pool_size | default(25) }}
```

Настройки pgbouncer:

```yaml
pgbouncer_admin: admindb

pgbouncer_instances:
 - pgbouncer
 - pgbouncer_1
 - pgbouncer_2
 - pgbouncer_3

pgbouncer_pool_mode: session|transaction
pgbouncer_max_client_conn: 10000
pgbouncer_default_pool_size: 600
```

```bash
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/10_postgres_users.yml
```

## 4. Установка odyssey и настройка <a name="odyssey"></a>

- установка сурцов и зависимостей
- билд и установка
- конфигурирование конфига и сервиса

Настройки:

```yaml
odyssey_pool_mode: session|transaction
odyssey_client_max: 10000
odyssey_pool_size: 600
odyssey_listen_port: 6433
odyssey_workers: 4
```

```bash
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/12_odyssey_config.yml
```

## 5. Проведение extended бенчмарков <a name="benchmarks"></a>

Условия:

- напрямую к `postgresql 5432` порт
- через `pgbouncer 6432` порт в режиме so_reuse_port с несколькими сервисами (так как один сервис пгбаунсер работает на 1 ядре )
- через `odyssey 6433` порт
- в режиме установления соединения на каждую транзакцию и нет `conn per tx`
- режимы работы пулов `session` и `transaction`
- одинаковое количество тредов пулеров


Настройки `VM` и `postgresql`:

| Параметр          | Стенд    |
|-------------------|----------|
| Версии PG         | 15       |
| RAM, Gb           | 16       |
| CPU               | 8        |
| Disk type         | SSD      |
| Db Size           | 10GB     |
| config            | default  |
| max_connections   | 1000     |

Настройки `pgbench`:

```yaml
pgbench_clients: 500
pgbench_jobs: 16
pgbench_time: 30
pgbench_workload_file: workload.sql
pgbench_postgresql_port: 5432 postgres | 6432 pgbouncer | 6433 odyssey
pgbench_external: True
pgbench_host: 127.0.0.1
pgbench_tx_per_conn: True | False
```

Настройки `odissey`:

```yaml
odyssey_pool_mode: session|transaction
odyssey_client_max: 10000
odyssey_pool_size: 600
odyssey_listen_port: 6433
odyssey_workers: 4
```

Настройки `pgbouncer`:

```yaml
pgbouncer_admin: admindb

pgbouncer_instances:
 - pgbouncer
 - pgbouncer_1
 - pgbouncer_2
 - pgbouncer_3

pgbouncer_pool_mode: session|transaction
pgbouncer_max_client_conn: 10000
pgbouncer_default_pool_size: 600
```

Общие результаты:

| Connection to --> |   postgres   |   postgres  |  pgbouncer  |   pgbouncer   |  pgbouncer  |   pgbouncer   |   odissey   |   odissey   |   odissey   |   odissey   |
|-------------------|--------------|-------------|-------------|---------------|-------------|---------------|-------------|-------------|-------------|-------------|
| postgres ver      | 15           | 15          | 15          | 15            | 15          | 15            | 15          | 15          | 15          | 15          |
| scale factor      | 1            | 1           | 1           | 1             | 1           | 1             | 1           | 1           | 1           | 1           |
| clients           | 500          | 500         | 500         | 500           | 500         | 500           | 500         | 500         | 500         | 500         |
| threads           | 16           | 16          | 16          | 16            | 16          | 16            | 16          | 16          | 16          | 16          |
| max num tries     | 1            | 1           | 1           | 1             | 1           | 1             | 1           | 1           | 1           | 1           |
| duration          | 30 s         | 30 s        | 30 s        | 30 s          | 30 s        | 30 s          | 30 s        | 30 s        | 30 s        | 30 s        |
| test type         | external     | external    | external    | external      | external    | external      | external    | external    | external    | external    |
| workload db       | thai_middle  | thai_middle | thai_middle | thai_middle   | thai_middle | thai_middle   | thai_middle | thai_middle | thai_middle | thai_middle |
| workload type     | workload.sql | workload.sql| workload.sql| workload.sql  | workload.sql|   workload.sql| workload.sql| workload.sql| workload.sql| workload.sql|
| pooler type       | none         | none        |  pgbouncer  |   pgbouncer   |  pgbouncer  |   pgbouncer   |   odissey   |   odissey   |   odissey   |   odissey   |
| pool mode         | session      | session     |  session    |  session      | transaction |  transaction  |  session    |  session    | transaction | transaction |
| conn per tx       | no           | yes         | no          | yes           | no          | yes           | no          | yes         | no          | yes         |
| failed txs        | 0            | 0           | 0           | 0             | 0           | 0             | 0           | 0           | 0           | 0           |
| proc txs          | 1442943      | 27302       | 972855      | 40062         | 1079810     | 42608         | 1213899     | 39262       | 634104      | 38866       |
| ltncy avg ms      | 10           | 550         | 15          | 374           | 13          | 352           | 12          | 382         | 23          | 386         |
| init/avg ctime ms | 475          | 17          | 440         | 11            | 428         | 10            | 430         | 12          | 431         | 12          |
| tps ms            | 48559        | 907         | 32888       | 1334          | 36496       | 1419          | 41036       | 1308        | 21426       | 1294        |

Выводы по результатам сравнения с пулером и без:

- в режиме `без conn per tx` лучшим результатом оказалось подключение `напрямую` без пулеров соединений
- в режиме `conn per tx` и режиме пулинга `session`, видим что `latency avg` уменьшилось `550ms` --> `374ms` , так же `tps` увеличилось с `907` --> `1334`и лидером в этом режиме становится `pgbouncer`
- в режиме `conn per tx` и режиме пулинга `transaction`, `latency avg` уменьшилось уже с `550ms` --> `352ms`, `tps` же увеличилось с `907` --> `1419`и лидером опять становится `pgbouncer`

Условия реальные:
 - клиент подключился
 - выполнил транзакцию
 - отключился
 - клиентов много типичная oltp нагрузка

Выводы:
 - установление соединений с postgres напрямую дорого!
 - использовать пулер например `pgbouncer` и желательно в режиме `transaction` pooling