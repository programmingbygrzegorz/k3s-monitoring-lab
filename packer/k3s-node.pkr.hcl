# Maszyna laboratorium budowana od zera z ISO Ubuntu Server (VMware Workstation).
# Instalacja bez klikania (autoinstall), od razu ze stałym IP, nazwą hosta i repozytorium.
#
#   packer init .
#   packer build "-var-file=k3s-worker-3.pkrvars.hcl" "-var-file=secrets.pkrvars.hcl" .

packer {
  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = ">= 1.1.0"
    }
  }
}

# --- obraz systemu ---

variable "iso_path" {
  type        = string
  description = "Ścieżka do ISO Ubuntu Server"
}

variable "iso_checksum" {
  type        = string
  description = "Suma kontrolna ISO, np. sha256:..."
}

# --- maszyna ---

variable "node_name" {
  type        = string
  description = "Nazwa maszyny w VMware i nazwa hosta, np. k3s-worker-3"
}

variable "node_ip" {
  type        = string
  description = "Stały adres IP maszyny"
}

variable "node_mac" {
  type        = string
  description = "Stały MAC karty z puli VMware 00:50:56:00:00:00 - 00:50:56:3F:FF:FF"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 6144
}

variable "disk_size" {
  type    = number
  default = 40960
}

variable "output_directory" {
  type        = string
  description = "Folder, w którym powstanie maszyna (nie może istnieć)"
}

# --- sieć ---

variable "iface" {
  type    = string
  default = "ens33"
}

variable "prefix" {
  type    = number
  default = 24
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "dns" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "lab_hosts" {
  type        = map(string)
  description = "Wszystkie maszyny laboratorium (nazwa = adres) do /etc/hosts"
  default     = {}
}

# --- użytkownik (secrets.pkrvars.hcl, poza repozytorium) ---

variable "username" {
  type = string
}

variable "password" {
  type      = string
  sensitive = true
}

variable "password_hash" {
  type        = string
  sensitive   = true
  description = "Hash hasła: openssl passwd -6"
}

variable "ssh_public_key_file" {
  type        = string
  description = "Klucz publiczny SSH wgrywany do authorized_keys"
  default     = "~/.ssh/k3s-lab.pub"
}

locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
}

variable "repo_url" {
  type    = string
  default = "https://github.com/programmingbygrzegorz/k3s-monitoring-lab.git"
}

source "vmware-iso" "k3s_node" {
  iso_url      = var.iso_path
  iso_checksum = var.iso_checksum

  vm_name          = var.node_name
  output_directory = var.output_directory
  guest_os_type    = "ubuntu-64"
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  headless         = false

  network              = "nat"
  network_adapter_type = "e1000"
  vmx_data = {
    # Jak w pozostałych maszynach: slot 33 daje w Ubuntu nazwę karty ens33
    "ethernet0.pciSlotNumber" = "33"
    "ethernet0.addressType"   = "static"
    "ethernet0.address"       = var.node_mac
  }

  # Pliki autoinstall serwowane przez Packera po HTTP
  http_content = {
    "/meta-data" = ""
    "/user-data" = templatefile("${path.root}/user-data.pkrtpl.yaml", {
      node_name      = var.node_name
      node_ip        = var.node_ip
      node_mac       = var.node_mac
      iface          = var.iface
      prefix         = var.prefix
      gateway        = var.gateway
      dns            = var.dns
      username       = var.username
      password_hash  = var.password_hash
      ssh_public_key = local.ssh_public_key
    })
  }

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=\"nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\"<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  # Po instalacji maszyna ma już stały adres – Packer łączy się bezpośrednio pod nim
  communicator = "ssh"
  ssh_host     = var.node_ip
  ssh_username = var.username
  ssh_password = var.password
  ssh_timeout  = "45m"

  shutdown_command = "echo '${var.password}' | sudo -S shutdown -P now"
}

build {
  sources = ["source.vmware-iso.k3s_node"]

  provisioner "shell" {
    execute_command = "echo '${var.password}' | sudo -S bash '{{ .Path }}'"
    inline = concat(
      ["sed -i -E '/^127\\./!{/[[:space:]](k3s-master|k3s-worker-[0-9]+|monitoring)([[:space:]]|$)/d}' /etc/hosts"],
      [for name, ip in var.lab_hosts : "echo '${ip} ${name} # k3s-lab' >> /etc/hosts"],
      # Hasło przez SSH działa tylko na czas budowy – gotowa maszyna przyjmuje wyłącznie klucz
      ["echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/99-lab.conf"]
    )
  }

  provisioner "shell" {
    inline = [
      "git clone ${var.repo_url} ~/k3s-monitoring-lab",
      "cp ~/k3s-monitoring-lab/lab.env.example ~/k3s-monitoring-lab/lab.env"
    ]
  }
}
