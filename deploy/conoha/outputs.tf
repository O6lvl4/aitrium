output "ipv4" {
  value = local.ipv4
}

output "ssh" {
  description = "Work as agent (no sudo); root is for administration"
  value       = "ssh agent@${local.ipv4}"
}

output "instance_id" {
  value = conohavps_instance.host.id
}
