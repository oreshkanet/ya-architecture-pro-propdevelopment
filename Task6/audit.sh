#!/bin/bash

AUDIT_LOG="${1:-./audit.log}"

jq -r '
  # Пропускаем не-объекты и не-события
  #select(type == "object" and .kind == "Event") |

  # Безопасно извлекаем поля
  (.objectRef // {}) as $obj |
  (.user // {}) as $user |
  
  (.requestObject // {}) as $req |
  ($req.spec // {}) as $spec |
  ($spec.containers // []) as $containers_raw |
  ($containers_raw | if type == "array" then . else [] end) as $containers |

  # Основные поля
  $user.username as $username |
  .verb as $verb |
  $obj.namespace as $ns |
  $obj.name as $name |
  $obj.resource as $resource |
  .requestURI as $uri |

  select(
    # 1. Доступ к секретам:
    ($resource=="secrets" and ($verb == "get" or $verb == "list")) 

    or

    # 2. Привилегированные поды
    ($resource == "pods" and $containers[].securityContext.privileged==true)
    #    ($containers | map(select(.securityContext.privileged == true)) | length > 0))

    or

    # 3. Использование kubectl exec в чужом поде
    ($verb=="create" and $resource=="exec") 
    
    or

    # 4. Создание RoleBinding с правами cluster-admin
    ($verb == "create" and $resource == "rolebindings" and
      (
        ($req.roleRef // {}).name == "cluster-admin" or
        ($req.roleRef // {}).name == "admin"
      )
    )

  )
' "$AUDIT_LOG"

# 5. Удаление audit-policy.yaml
grep -i 'audit-policy' "$AUDIT_LOG"