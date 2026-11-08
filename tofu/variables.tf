variable "pve_endpoint" {
  type        = string
  default     = ""
  description = "Proxmox API endpoint; empty = pve-1 from ansible/group_vars"
}

variable "pve_username" {
  type        = string
  default     = "root@pam"
  description = "Proxmox API user; root@pam required for lxc bind mounts"
}

variable "pve_api_token" {
  type        = string
  sensitive   = true
  default     = ""
  description = "root@pam API token 'root@pam!id=uuid' — 2fa-exempt, primary auth. create: pveum user token add root@pam terraform --privsep 0"
}

variable "pve_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "root@pam password; only for lxc bind-mount ops the api denies tokens. blank for normal runs (2fa blocks it anyway)"
}

variable "vm_password" {
  type        = string
  sensitive   = true
  description = "cloud-init password for the admin user (VMs) / root (LXC); match the ansible sudo_pass"
}

variable "vm_datastore" {
  type        = string
  default     = "local-lvm"
  description = "datastore for vm/ct disks and cloud-init drives"
}

variable "image_datastore" {
  type        = string
  default     = "local"
  description = "datastore holding the downloaded cloud image (per node)"
}

variable "debian_image_url" {
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  description = "debian cloud image (qcow2)"
}

variable "lxc_template" {
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
  description = "OS template for the LXCs, on every node that runs one (pveam download local ...)"
}

variable "haos_image" {
  type        = string
  default     = "local:import/haos.qcow2"
  description = "home assistant os disk image on pve-3, unpacked by hand (upstream ships .qcow2.xz, pve can't unpack xz), see README"
}
