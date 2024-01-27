# PG_Homeworks


## Подготовка

1. Получаем OAUTH_TOKEN для своего аккаунта:

`https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb`

2. Подготовим yacloud_compute.yml для инвентори плагина

```
plugin: yacloud_compute
yacloud_clouds:
 - cloud-brusnicin
yacloud_folders:
 - default
yacloud_token: "OAUTH_TOKEN"
```

3. Подготовка окружения:

Создаем виртуальное окружение и активируем:
`python3 -m venv .venv && source .venv/bin/activate`

Устанавливаем зависимости:
`python3 -m pip install --upgrade pip && python3 -m pip install --no-cache-dir -r requirements.txt`

4. Подготовка инвентори и окружения:

`ansible-playbook --vault-password-file=~/vault_test_file -i inventory/group_vars/all/yacloud_compute.yml -i inventory playbooks/1_createvm.yml`

`ansible-playbook --vault-password-file=~/vault_test_file -i inventory/group_vars/all/yacloud_compute.yml -i inventory playbooks/<название плейбука>.yml`


