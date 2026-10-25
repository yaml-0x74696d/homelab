terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint = local.pve_endpoint
  insecure = true # self-signed pve certs

  # api token is exempt from 2fa — primary auth for plan/apply. null => fall back to user/pass.
  api_token = var.pve_api_token != "" ? var.pve_api_token : null

  # root@pam pw: only for the privileged ops the api won't do with a token (lxc bind mounts).
  # leave blank for normal runs; fill it + temporarily disable 2fa when (re)creating the storage lxc.
  username = var.pve_username
  password = var.pve_password != "" ? var.pve_password : null

  # some operations (disk import, file uploads) need ssh to the node
  ssh {
    agent    = true
    username = "root"
  }
}
