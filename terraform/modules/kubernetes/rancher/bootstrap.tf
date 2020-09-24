resource "null_resource" "wait_for_rancher" {
  count = var.bootstrap_rancher ? 1 : 0

  depends_on = [helm_release.rancher]
  provisioner "local-exec" {
    command = "count=0; until $(curl -ks --connect-timeout 3 ${join("", ["https://", var.cluster_nodes[0].ip, ".nip.io"])} | grep cattle > /dev/null 2>&1); do sleep 1; if [ $count -eq 100 ]; then break; fi; count=`expr $count + 1`; done"
  }
}

provider "rancher2" {
  alias = "bootstrap"

  api_url   = join("", ["https://", var.cluster_nodes[0].ip, ".nip.io"])
  bootstrap = true
  insecure  = true
}

resource "rancher2_bootstrap" "admin" {
  count = var.bootstrap_rancher ? 1 : 0

  provider   = rancher2.bootstrap
  depends_on = [null_resource.wait_for_rancher[0]]

  password  = var.rancher_password
  telemetry = true
}

provider "rancher2" {
  alias = "admin"

  api_url   = var.bootstrap_rancher ? rancher2_bootstrap.admin[0].url : ""
  token_key = var.bootstrap_rancher ? rancher2_bootstrap.admin[0].token : ""
  insecure  = true
}

data "dns_a_record_set" "vcenter" {
  host = var.rancher_vsphere_server
}

resource "rancher2_cloud_credential" "vsphere" {
  count = var.bootstrap_rancher ? 1 : 0

  provider    = rancher2.admin
  name        = "vsphere"
  description = "vsphere"
  vsphere_credential_config {
    username     = var.rancher_vsphere_username
    password     = var.rancher_vsphere_password
    vcenter      = data.dns_a_record_set.vcenter.addrs[0]
    vcenter_port = var.rancher_vsphere_port
  }
}

resource "rancher2_setting" "server_url" {
  count      = var.bootstrap_rancher ? 1 : 0
  provider   = rancher2.admin
  depends_on = [rancher2_node_template.vsphere]

  name  = "server-url"
  value = join("", ["https://", var.rancher_server_url])
}

data "template_file" "kickstart_userdata" {
  count    = var.bootstrap_rancher ? 1 : 0
  template = file("${path.module}/templates/kickstart-userdata.yaml.tpl")
  vars = {
    ssh_public_key = var.ssh_public_key
  }
}

data "template_file" "userdata" {
  count    = var.bootstrap_rancher ? 1 : 0
  template = file("${path.module}/templates/userdata.yaml.tpl")
}

resource "rancher2_node_template" "vsphere" {
  count = var.bootstrap_rancher ? 1 : 0

  name     = "default-vsphere"
  provider = rancher2.admin

  description         = "vsphere"
  cloud_credential_id = rancher2_cloud_credential.vsphere[0].id
  vsphere_config {
    cpu_count     = var.user_cluster_cpu
    memory_size   = var.user_cluster_memoryMB
    datacenter    = var.rancher_vsphere_datacenter
    datastore     = var.rancher_vsphere_datastore
    disk_size     = var.rancher_node_template_disk_size
    folder        = var.rancher_vsphere_folder
    network       = [var.rancher_vsphere_network]
    pool          = var.rancher_vsphere_pool
    creation_type = "template"
    clone_from    = var.user_cluster_template
    cloudinit     = data.template_file.userdata[0].rendered
    vapp_property = [
      "user-data=${data.template_file.kickstart_userdata[0].rendered}"
    ]
  }
}

resource "rancher2_cluster" "cluster" {
  count    = var.create_user_cluster && var.bootstrap_rancher ? 1 : 0
  name     = var.user_cluster_name
  provider = rancher2.admin

  description = "Default user cluster"
  rke_config {
    network {
      plugin = "canal"
    }
  }
}

resource "rancher2_node_pool" "control_plane" {
  count = var.create_user_cluster && var.bootstrap_rancher ? 1 : 0

  cluster_id       = rancher2_cluster.cluster[0].id
  provider         = rancher2.admin
  name             = join("", [var.user_cluster_name, "-control-plane"])
  hostname_prefix  = join("", [var.user_cluster_name, "-cp-0"])
  node_template_id = rancher2_node_template.vsphere[0].id
  quantity         = 1
  control_plane    = true
  etcd             = true
  worker           = false
}

resource "rancher2_node_pool" "worker" {
  count = var.create_user_cluster && var.bootstrap_rancher ? 1 : 0

  cluster_id       = rancher2_cluster.cluster[0].id
  provider         = rancher2.admin
  name             = join("", [var.user_cluster_name, "-workers"])
  hostname_prefix  = join("", [var.user_cluster_name, "-wrk-0"])
  node_template_id = rancher2_node_template.vsphere[0].id
  quantity         = 2
  control_plane    = false
  etcd             = false
  worker           = true
}

resource "local_file" "kubeconfig_user" {
  count = var.create_user_cluster && var.bootstrap_rancher ? 1 : 0

  filename = format("${local.deliverables_path}/kubeconfig_user")
  content  = rancher2_cluster.cluster[0].kube_config
}

resource "local_file" "rancher_api_key" {
  count = var.bootstrap_rancher ? 1 : 0

  filename = format("${local.deliverables_path}/rancher_token")
  content  = rancher2_bootstrap.admin[0].token
}

data "http" "trident_installer_crd" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0
  url   = "https://raw.githubusercontent.com/netapp/TridentInstaller/master/deploy/crds/tridentinstall.czan.io_tridentinstallations_crd.yaml"
}

data "http" "trident_installer_operator" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0
  url   = "https://raw.githubusercontent.com/netapp/TridentInstaller/master/deploy/operator.yaml"
}

data "http" "trident_installer_role" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0
  url   = "https://raw.githubusercontent.com/netapp/TridentInstaller/master/deploy/role.yaml"
}

data "http" "trident_installer_rolebinding" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0
  url   = "https://raw.githubusercontent.com/netapp/TridentInstaller/master/deploy/role_binding.yaml"
}

data "http" "trident_installer_serviceaccount" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0
  url   = "https://raw.githubusercontent.com/netapp/TridentInstaller/master/deploy/service_account.yaml"
}

data "template_file" "trident_namespace" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0

  template = file("${path.module}/templates/trident_ns.yaml.tpl")
}

data "template_file" "trident_installation" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0

  template = file("${path.module}/templates/trident_installation.yaml.tpl")
  vars = {
    trident_username = var.trident_username
    trident_password = var.trident_password
    tenant_name      = var.trident_tenant_name
    svip             = var.trident_svip
    mvip             = var.trident_mvip
    use_chap         = var.trident_use_chap
  }
}

resource "rancher2_cluster_template" "template" {
  count = var.bootstrap_rancher && var.create_trident_cluster_template ? 1 : 0

  name     = "trident-default"
  provider = rancher2.admin
  template_revisions {
    name    = "v1"
    default = true
    cluster_config {
      rke_config {
        addons = <<EOT
${data.template_file.trident_namespace[0].rendered}
---
${data.http.trident_installer_crd[0].body}
---
${data.http.trident_installer_operator[0].body}
---
${data.http.trident_installer_role[0].body}
---
${data.http.trident_installer_rolebinding[0].body}
---
${data.http.trident_installer_serviceaccount[0].body}
---
${data.template_file.trident_installation[0].rendered}
EOT
      }
    }
  }
}
