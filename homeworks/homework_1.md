# Домашнее задание #1

## Задача

1. [Подготовить виртуальные машины](#createvm)
2. [Установка, настройка postgresql и прикладного ПО](#installpg)
3. [Провести бенчмарки с разными параметрами](#benchmarks)
4. [Настроить на оптимальную производительность](#optimize)
5. [Настроить на максимальную производительность жертвуя надежностью](#maxoptimize)
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
    memory: 8192
    cores: 4 
    disks:
      - name: scsi0
        size: 100
        state: resized
  - name: pg15
    memory: 8192
    cores: 4
    disks:
      - name: scsi0
        size: 100
        state: resized
```

### 1.2 Создание ВМ: 

Плейбук:

```
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts.ini playbooks/1_pvecreate.yml -v
ansible-playbook --vault-password-file ~/vault_test_file -i inventory/hosts.ini playbooks/1_pvecreate.yml -v -t start
```
## 2. Установка, настройка postgresql и прикладного ПО <a name="installpg"></a>

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
    value: 120
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

Плейбук запуска:
```
ansible-playbook --vault-password-file=~/vault_test_file -i inventory/hosts playbooks/8_benchmark.yml -e pgbench_vacuumfull=true
```

### 3.1 С дефолтным конфигом






