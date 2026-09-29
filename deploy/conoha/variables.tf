variable "name" {
  description = "Name of the server and the prefix of what goes with it"
  type        = string
  default     = "aitrium"
}

variable "flavor" {
  description = "ConoHa plan by flavor name: g2l-t-c3m2 is Linux, hourly billing, 3 cores, 2 GB (2,033 yen a month at most)"
  type        = string
  default     = "g2l-t-c3m2"
}

variable "image" {
  description = "OS image by name. aitrium's host check runs on Ubuntu 22.04 and 24.04"
  type        = string
  default     = "vmi-ubuntu-24.04-amd64"
}

variable "ssh_public_key" {
  description = "Public key for root and for the agent user"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "aitrium_version" {
  description = "Release tag install.sh installs, or latest"
  type        = string
  default     = "latest"
}

variable "swap_gb" {
  description = "Swap file size in GB, so an agent's build or test run does not meet the OOM killer on a small plan; 0 for none"
  type        = number
  default     = 2
}
