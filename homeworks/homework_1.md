# Домашнее задание #1

## Задача

1. [Подготовить виртуальные машины](#createvm)
2. [Установка, настройка postgresql и прикладного ПО](#install)
3. [Провести бенчмарки с разными параметрами](#benchmarks)
4. [Настроить на оптимальную производительность](#optimize)
5. [Настроить на максимальную производительность жертвуя надежностью](#dangeroptimize)
6. [Результаты](#results)

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
  - name: pg14
    memory: 16384
    cores: 8
    disks:
      - name: scsi0
        size: 100
        #cache: unsafe
        iothread: true
        ssd : true
  - name: pg15
    memory: 16384
    cores: 8
    disks:
      - name: scsi0
        size: 100
        #cache: unsafe
        iothread: true
        ssd : true
```

### 1.2 Создание ВМ: 

Плейбук:

```
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts.ini playbooks/1_pvecreate.yml -v
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts.ini playbooks/1_pvecreate.yml -v -t start
```
## 2. Установка, настройка postgresql и прикладного ПО <a name="install"></a>

### 2.1 Установка дополнительных утилит и обновление базовых пакетов

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/2_install_common.yml
```

### 2.2 Установка настроек sysctl и sysfs

Значения:
```
sysctl_params:
  - name: vm.swappiness
    value: 5
    state: present
  - name: vm.nr_hugepages
    value: 2200
    state: present
  - name: vm.overcommit_memory
    value: 2
    state: present
  - name: vm.overcommit_ratio
    value: 50
    state: present

kernel/mm/transparent_hugepage/enabled = never
```

- Установка Hugepages
- Отключение Transparent Huge Pages
- Сеттинг оверкоммит и swappiness


```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/3_sysctl.yml
```

### 2.3 Настройка swap файла подкачки

Значения:

```
swap_file_size_mb: "{{ [(ansible_memory_mb.real.total / 3), 65536] | min | int }}"
```

- 1/3 от Total VM RAM

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/4_swap.yml
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

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/7_prepare_workload.yml
```

## 3. Проведение бенчмарков c pgbench <a name="benchmarks"></a>

Настройки pgbench:
```
pgbench_clients: 20
pgbench_jobs: 8
pgbench_time: 30
pgbench_workload_file: workload.sql
pgbench_vacuumfull: false
pgbench_builtin_workload: tpcb-like
pgbench_protocol: simple|extended
```

- Выполнение вакуума full по требованию для external workload
- Выполнение принудительного вакуума встроенных таблиц pgbench
- Запуск бенчмарка


Тесты:

- SIMPLE: - встроенный pgbench тест с протоколом simple
- EXTENDED: - встроенный pgbench тест с протоколом extended
- EXTERNAL: - внешний workload.sql по базе middle

Плейбук запуска:
```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/8_benchmark.yml -e pgbench_vacuumfull=true
```

### 3.1 С дефолтным конфигом postgresql

Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 16       | 16       |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | default  | default  |


Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 9108          | 9009        | 1996681     | 9108          | 9080        | 1935060     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 65.989        | 66.715      | 0.300       | 65.989        | 66.190      | 0.310       |
| init conn time ms | 11.703        | 11.819      | 11.725      | 11.703        | 12.599      | 10.916      |
| tps (w/0 ict) ms  | 303.081690    | 299.784810  | 66580.466145| 302.160870    | 299.784810  | 64509.100302|



Выводы:
 - судя по atop и iostat упиралось все в дисковую подсистему особенно видно по тестам tpc-b
 - thai middle очень эффективно из кеша берет данные, в целом результаты те же в разных версиях pg

### 3.2 С конфигом от cybertec


Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 16       | 16       |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | cybertec | cybertec |


Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 9129          | 9091        | 2060958     | 9023          | 9026        | 2002237     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 65.841        | 66.117      | 0.291       | 66.606        | 66.595      | 0.300       |
| init conn time ms | 11.256        | 11.052      | 11.150      | 13.891        | 11.541      | 12.002      |
| tps (w/0 ict) ms  | 303.763463    | 302.496110  | 68722.185454| 300.274817    | 300.322562  | 66712.531379|



Выводы:
- аналогично упираемся в диски по производительности в тестах tpc-b не справляются
- после изменения конфига от cybertec увеличились tps примерно на 1-3% на thai middle тестах
## 4. Настроить на оптимальную производительность <a name="optimize"></a>

### 4.1 Включение Swap + Sysctl и Sysfs параметры

- включение hugepages
- включение swap 1/3 части RAM
- выключение transparent huge pages


```
sysctl_params:
  - name: vm.swappiness
    value: 5
    state: present
  - name: vm.nr_hugepages
    value: 2200
    state: present
  - name: vm.overcommit_memory
    value: 2
    state: present
  - name: vm.overcommit_ratio
    value: 50
    state: present

```

Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 16       | 16       |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | cybertec | cybertec |
| hugepages         | on       | on       |
| swap              | on       | on       |
| thp               | off      | off      |

Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 9121          | 9111        | 2022163     | 8815          | 8945        | 2056727     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 65.900        | 65.975      | 0.297       | 68.186        | 67.194      | 0.292       |
| init conn time ms | 11.564        | 11.691      | 10.857      | 12.766        | 11.810      | 11.223      |
| tps (w/0 ict) ms  | 303.492146    | 303.147171  | 67427.987995| 293.316841    | 297.644657  | 68573.731781|


Выводы:
 - судя по atop и iostat упиралось все в дисковую подсистему особенно видно по тестам tpc-b
 - какого либо значимого улучшения производительности от версии или от текущих параметров не повлияло 
 - thai middle очень эффективно из кеша берет данные, в целом результаты те же в разных версиях pg
 - списываем на погрешность в среднем не изменилось значительно

### 4.2 Тюним параметры postgresl и sysfs

- тюним шедулер дисковой none --> mq-deadline
- effective_io_concurrency 100 --> 200
- max_parallel_workers 8 --> 16
- default_statistics_target 200 --> 500
- max_wal_size 2GB --> 4GB

Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 16       | 16       |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | cybertec | cybertec |
| hugepages         | on       | on       |
| swap              | on       | on       |
| thp               | off      | off      |
| disk scheduler|mq-deadline|mq-deadline|
|effective_io_concurrency| 200      | 200      |
|default_statistics_target|500|500|
|max_parallel_workers|16|16|
|jit|off|off|
|max_wal_size|4GB|4GB|


Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 9027          | 8988        | 2014400     | 8952          | 8965        | 2021844     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 66.585        | 66.877      | 0.298       | 67.139        | 67.046      | 0.297       |
| init conn time ms | 11.932        | 11.364      | 11.098      | 11.559        | 11.182      | 11.558      |
| tps (w/0 ict) ms  | 300.368068    | 299.056624  | 67165.378941| 297.889695    | 298.302802  | 67419.396843|



Выводы:
 - все сводит на нет упор в дисковую подсистему в тестах tpc-b
 - какого либо улучшения или ухудшения нет, списываем на погрешность


## 5. Настроить на максимальную производительность жертвуя надежностью <a name="dangeroptimize"></a>

### 5.1 Пускаемся во все тяжкие, не думаем о сохранности:

- synchronous_commit --> off
- fsync --> off
- full_page_writes --> off
- proxmox disk cache=writeback (unsafe) --> on (игронирование flush() вызовов с guest vm)

Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 16       | 16       |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | cybertec | cybertec |
| hugepages         | on       | on       |
| swap              | on       | on       |
| thp               | off      | off      |
| disk scheduler|mq-deadline|mq-deadline|
|effective_io_concurrency| 200      | 200      |
|default_statistics_target|500|500|
|max_parallel_workers|16|16|
|jit|off|off|
|max_wal_size|4GB|4GB|
|synchronous_commit|off|off|
|fsync|off|off|
|full_page_writes|off|off|
|disk writeback unsafe|on|on|


Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 116882        | 108331      | 1987496     | 116322        | 107387      | 1980972     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 5.133         | 5.538       | 0.302       | 5.157         | 5.587       | 0.303       |
| init conn time ms | 12.382        | 11.987      | 11.471      | 12.508        | 12.264      | 11.985      |
| tps (w/0 ict) ms  | 3896.486578   | 3611.699692 | 66272.576069| 3877.973811   | 3579.982780 | 66057.352064|



|
Выводы:
 - диски теперь не узкое место, жертвуя надежностью прибавка более чем x10 раз
 - упираемся уже в lock wait события на доступ ниже таблица по tpc-b
 - по тесту thai middle упираемся в ресурсы cpu



| ts_age  | change_age | datname  | usename  | client_addr | pid  | state  | lvl | blocked |                                    query                                     
|---------|------------|----------|----------|-------------|------|--------|-----|---------|------------------------------------------------------------------------------|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2038 | idletx |   0 |      13 |  UPDATE pgbench_branches SET bbalance = bbalance + 3161 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2020 | active |   1 |       0 |  . UPDATE pgbench_branches SET bbalance = bbalance + 2393 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2027 | active |   1 |      11 |  . UPDATE pgbench_branches SET bbalance = bbalance + 4162 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2016 | active |   2 |       8 |  . . UPDATE pgbench_branches SET bbalance = bbalance + -242 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2017 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -3965 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2021 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + 2420 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2025 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -3697 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2028 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -4276 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2029 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -2584 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2031 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + 918 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2037 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -1221 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2041 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + 2548 WHERE tid = 8;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2018 | active |   2 |       1 |  . . UPDATE pgbench_branches SET bbalance = bbalance + -2005 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2023 | active |   3 |       0 |  . . . UPDATE pgbench_tellers SET tbalance = tbalance + -2415 WHERE tid = 3;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2044 | active |   0 |       4 |  UPDATE pgbench_branches SET bbalance = bbalance + 4733 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2032 | active |   1 |       2 |  . UPDATE pgbench_branches SET bbalance = bbalance + -2142 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2019 | active |   2 |       0 |  . . UPDATE pgbench_tellers SET tbalance = tbalance + 3138 WHERE tid = 5;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2040 | active |   2 |       0 |  . . UPDATE pgbench_tellers SET tbalance = tbalance + -2512 WHERE tid = 5;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2033 | active |   1 |       0 |  . UPDATE pgbench_tellers SET tbalance = tbalance + -4063 WHERE tid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2035 | active |   0 |       1 |  UPDATE pgbench_tellers SET tbalance = tbalance + 1891 WHERE tid = 6;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2034 | active |   1 |       0 |  . UPDATE pgbench_tellers SET tbalance = tbalance + -2148 WHERE tid = 6;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2022 | active |   0 |       6 |  UPDATE pgbench_branches SET bbalance = bbalance + -2076 WHERE bid = 1;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2030 | active |   1 |       0 |  . UPDATE pgbench_tellers SET tbalance = tbalance + -3724 WHERE tid = 7;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2036 | active |   1 |       0 |  . UPDATE pgbench_tellers SET tbalance = tbalance + 362 WHERE tid = 7;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2039 | active |   1 |       0 |  . UPDATE pgbench_tellers SET tbalance = tbalance + 1213 WHERE tid = 7;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2043 | active |   1 |       2 |  . UPDATE pgbench_tellers SET tbalance = tbalance + 3244 WHERE tid = 7;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2024 | active |   2 |       0 |  . . UPDATE pgbench_tellers SET tbalance = tbalance + 1055 WHERE tid = 7;|
|00:00:00 | 00:00:00   | postgres | postgres |             | 2042 | active |   2 |       0 |  . . UPDATE pgbench_tellers SET tbalance = tbalance + 902 WHERE tid = 7;|



### 5.2 Делаем редис из постгреса используя ram disk:

```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/9_ramdisk.yml -t tmpfs
```

- увеличим до 32GB ram
- создаем рам диск 16GB и примонтируем к дата директории
- реинициализируем кластер
- снова готовим конфиги, инициализируем и загружаем тестовые данные для ворклоада

Условия:

| Параметр          | Стенд 1  | Стенд 2  |
|-------------------|----------|----------|
| Версии PG         | 14       | 15       |
| RAM, Gb           | 32       | 32      |
| CPU               | 8        | 8        |
| Disk type         | SSD      | SSD      |
| Db Size           | 10GB     | 10GB     |
| DB Type           | OLTP     | OLTP     |
| Connections       | 40       | 40       |
| PGCONFIG          | cybertec | cybertec |
| hugepages         | on       | on       |
| swap              | on       | on       |
| thp               | off      | off      |
| Data Directory    | in-memory|in-memory |



Результаты:

| Workload Type     | tpc-b smpl    | tpc-b extd  | Thai Middl  | tpc-b smpl    | tpc-b extd  | Thai Middl  |
|-------------------|---------------|-------------|-------------|---------------|-------------|-------------|
| postgres ver      | 14            | 14          | 14          | 15            | 15          | 15          |
| scale factor      | 1             | 1           | 1           | 1             | 1           | 1           |
| clients           | 20            | 20          | 20          | 20            | 20          | 20          |
| threads           | 8             | 8           | 8           | 8             | 8           | 8           |
| max num tries     | 1             | 1           | 1           | 1             | 1           | 1           |
| duration          | 30 s          | 30 s        | 30 s        | 30 s          | 30 s        | 30 s        |
| test type         | simple        | extended    | external    | simple        | extended    | external    |
| proc txs          | 115652        | 107690      | 2060155     | 116439        | 107056      | 1993618     |
| failed txs        | 0             | 0           | 0           | 0             | 0           | 0           |
| ltncy avg ms      | 5.187         | 5.571       | 0.291       | 5.152         | 5.603       | 0.301       |
| init conn time ms | 11.912        | 11.879      | 11.572      | 12.153        | 14.636      | 11.540      |
| tps (w/0 ict) ms  | 3855.433318   | 3590.000537 | 68696.522864| 3881.819387   | 3569.539229 | 66473.427774|

|
Выводы:
 - Результаты при выключении fsync и использовании ram диск идентичные
 - По сути выключение fsync равносильно писать в RAM