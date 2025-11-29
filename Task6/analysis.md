# Отчёт по результатам анализа Kubernetes Audit Log

## Подозрительные события

1. **Доступ к секретам**:
   - **Кто**: `system:serviceaccount:secure-ops:monitoring`
   - **Где**: обращение к `secrets` в namespace `kube-system`
   - **Почему подозрительно**: Учётная запись `monitoring` не должна иметь доступа к секретам в `kube-system`. Это указывает на избыточные права или отсутствие RBAC-ограничений.

2. **Привилегированные поды**:
   - **Кто**: `minikube-user`
   - **Комментарий**: Создан Pod `privileged-pod` с `securityContext.privileged: true`. Это позволяет обойти ограничения Container Runtime и получить доступ к хост-системе (например, `/proc`, `/dev`, `hostPath`).

3. **Использование `kubectl exec` в чужом поде**:
   - **Кто**: Инициатор — `system:admin`
   - **Что делал**: Выполнение `kubectl exec` в `coredns-*` Pod в `kube-system` для чтения `/etc/resolv.conf`. Чтение системных файлов в критичном Pod.

4. **Создание RoleBinding с правами `cluster-admin`**:
   - **Кто**: `system:admin`
   - **К чему привело**: Привязка `monitoring` к `ClusterRole/cluster-admin` для получения полного контроля над кластером.
5. **Удаление `audit-policy.yaml`**:
   - **Кто**: `system:admin`
   - **Возможные последствия**: Удаление политики аудита, после чего действия не логируются или логируются лишь на уровне `Metadata`. Признак маскировки следов.

## Вывод

Кластер скомпрометирован:  
- Сначала был осуществлён **несанкционированный доступ к секретам** (возможно, через отсутствие `NetworkPolicy` + избыточные RBAC-права у `monitoring`).  
- Затем создан **привилегированный Pod** — возможна эскалация до хоста.  
- Через `exec` в `coredns` — сбор информации о DNS-инфраструктуре.  
- Удаление `audit-policy.yaml` и создание `RoleBinding` для получения **полномасштабный контроля**.  

**Рекомендации**:  
- Немедленно отозвать `monitoring` SA: `kubectl delete sa monitoring -n secure-ops`.  
- Удалить `escalate-binding`.  
- Восстановить `audit-policy.yaml` и включить `RequestResponse` для `secrets`, `rolebindings`, `pods/exec`. 
- Ограничить `monitoring` минимальными правами (`view` в своём namespace).