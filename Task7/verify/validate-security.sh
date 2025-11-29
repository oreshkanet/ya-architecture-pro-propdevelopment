#!/bin/bash
set -euo pipefail

NS="audit-zone"

echo "Аудит существующих подов на соответствие политикам..."

# Функция проверки securityContext всех контейнеров
check_pod() {
  local pod=$1 ns=$2
  local output
  output=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null)

  # Проверяем каждое условие по отдельности — читаемо и отлаживаемо
  echo "$output" | jq -e '.spec.containers[0].securityContext.privileged == true' >/dev/null && { echo "privileged=true"; return 1; }
  echo "$output" | jq -e '.spec.containers[0].securityContext.runAsNonRoot != true' >/dev/null && { echo "runAsNonRoot != true"; return 1; }
  echo "$output" | jq -e '.spec.containers[0].securityContext.readOnlyRootFilesystem != true' >/dev/null && { echo "readOnlyRootFilesystem != true"; return 1; }
  echo "$output" | jq -e '.spec.containers[0].securityContext.allowPrivilegeEscalation == true' >/dev/null && { echo "allowPrivilegeEscalation=true"; return 1; }
  echo "$output" | jq -e '(.spec.containers[0].securityContext.capabilities.drop // []) != ["ALL"]' >/dev/null && { echo "capabilities.drop must be [\"ALL\"]"; return 1; }

  return 0
}

echo "Безопасные поды:"
for pod in pod-privileged-safe pod-hostpath-safe pod-root-user-safe; do
  pod_name=$(kubectl get pod "$pod" -n "$NS" --no-headers -o custom-columns=":metadata.name" 2>/dev/null)

  if [[ -n "$pod_name" ]]; then
    echo "  $pod:"
    if check_pod "$pod" "$NS" 2>&1; then
      echo "    OK"
    else
      echo "    FAIL"
    fi
  else
    echo "  $pod: not found"
  fi
done

echo "Проверка через Gatekeeper status:"
if kubectl get constraintpodstatuses.status.gatekeeper.sh &>/dev/null; then
  kubectl get constraint -o=custom-columns=NAME:.metadata.name,KIND:.kind,VIOLATIONS:.status.totalViolations 2>/dev/null || true
else
  echo "Gatekeeper не установлен"
fi

echo "Аудит завершён."