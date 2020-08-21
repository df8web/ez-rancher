---
apiVersion: tridentinstall.czan.io/v1alpha1
kind: TridentInstallation
metadata:
  name: trident-installation
  namespace: trident
spec:
  trident_username: ${trident_username}
  trident_password: ${trident_password}
  tenant_name: ${tenant_name}
  svip: ${svip}
  mvip: ${mvip}
  backend_name: solidfire
  storage_driver_name: solidfire-san
  use_chap: ${use_chap}