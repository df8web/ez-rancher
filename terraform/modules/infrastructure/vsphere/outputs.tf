locals {
  node_ips_no_mask = split("\n", replace(join("\n", var.static_ip_addresses), "/\\/.*/", ""))
}

output "nodes" {
  value = [
    for index, node in vsphere_virtual_machine.node :
    {
      name = node.name
      ip   = local.num_addresses == 0 ? node.default_ip_address : local.node_ips_no_mask[index]
    }
  ]
}

output "ssh_public_key" {
  value = tls_private_key.key.public_key_openssh
}

output "ssh_private_key" {
  value     = tls_private_key.key.private_key_pem
  sensitive = true
}

output "guestinfo_userdata" {
  value = data.template_file.userdata.rendered
  sensitive = true
}

output "kickstart_userdata" {
  value = base64encode(data.template_file.kickstart_userdata[0].rendered)
  sensitive = true
}