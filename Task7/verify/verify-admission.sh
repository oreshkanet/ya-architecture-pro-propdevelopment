#!/bin/bash
set -euo pipefail

NS="audit-zone"

echo "Создание namespace..."
kubectl apply -f ./01-create-namespace.yaml

echo "Ожидание 5 секунд для активации PodSecurity..."
sleep 5

echo "Попытка развернуть небезопасные поды:"
fail_count=0

for f in ./insecure-manifests/*.yaml; do
  echo " - $f"
  if kubectl apply -f "$f" 2>&1; then
    echo "   SUCCESS"
    ((fail_count++))
  else
    exit_code=$?
    echo "   REJECTED (exit $exit_code)"
  fi
done

echo "OPA Gatekeeper"
if ! kubectl get crd constrainttemplates.templates.gatekeeper.sh &>/dev/null; then
  echo "Gatekeeper not found"
  $fail_count++
else
  echo "Установка constraint templates и constraints"
  kubectl apply -f ./gatekeeper/constraint-templates/
  kubectl apply -f ./gatekeeper/constraints/
  sleep 10
fi

echo "Развертывание безопасных подов (ожидается SUCCESS):"
success_count=0
for f in ./secure-manifests/*.yaml; do
  echo " - $f"
  if kubectl apply -f "$f" &>/dev/null; then
    echo "   SUCCESS"
    ((success_count++))
  else
    echo "   FAILED (should have passed)"
    kubectl apply -f "$f"
  fi
done

# Проверка PodSecurity enforcement
echo "Проверка активности PodSecurity enforce:"
ps_label=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
if [[ "$ps_label" == "restricted" ]]; then
  echo " - PodSecurity enforce=restricted подтверждён"
else
  echo " - PodSecurity enforce НЕ установлен"
  ((fail_count++))
fi

# Проверка Gatekeeper
if kubectl get crd constraintpodstatuses.status.gatekeeper.sh &>/dev/null; then
  echo "Gatekeeper установлен — проверка constraints:"
  kubectl get k8snohostpath,k8spspprivileged,k8srequiredrunasnonroot -o name
else
  echo "Gatekeeper не установлен — ограничения PodSecurity работают отдельно"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Безопасные поды: $success_count/3"
echo "Небезопасные поды отклонены: $((3 - fail_count))/3"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $fail_count -eq 0 && $success_count -eq 3 ]]; then
  echo "ВСЁ ПРОЙДЕНО: политики работают корректно."
  exit 0
else
  echo "ОШИБКИ: проверка не пройдена."
  exit 1
fi