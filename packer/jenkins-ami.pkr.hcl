packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  default = "ap-southeast-3"
}

data "amazon-ami" "al2023_arm64" {
  filters = {
    name                = "al2023-ami-minimal-*-arm64"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.region
}

source "amazon-ebs" "jenkins" {
  ami_name      = "jenkins-ami-{{timestamp}}"
  instance_type = "t4g.small"
  region        = var.region
  source_ami    = data.amazon-ami.al2023_arm64.id
  ssh_username  = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 4
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "jenkins-custom-ami"
    Builder = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.jenkins"]

  # provisioner "shell" {
  #   inline = [
  #     "sudo curl -sLo /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
  #     "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
  #     "sudo dnf update -y",
  #     "sudo dnf install -y java-25-amazon-corretto git vim bind-utils docker amazon-ssm-agent jenkins",
  #     "sudo usermod -aG docker jenkins",
  #     "sudo dnf clean all",
  #     "sudo rm -rf /var/cache/dnf /tmp/* /var/tmp/*",
  #     "sudo journalctl --vacuum-size=0"
  #   ]
  # }

  # provisioner "shell" {
  #   inline = [
  #     "df -h /",
  #     "lsblk",
  #     # force-grow in case cloud-init didn't, AL2023 root is usually xvda/nvme0n1 part 4 or 1
  #     "sudo growpart $(findmnt -no SOURCE / | sed 's/[0-9]*$//') $(findmnt -no SOURCE / | grep -o '[0-9]*$') || true",
  #     "sudo xfs_growfs / || true",
  #     "df -h /",   # <-- this second df should now show the full volume
  #   ]
  # }

  # provisioner "shell" {
  #   inline = [
  #     "sudo dnf clean all",
  #     "sudo rm -rf /var/cache/dnf /tmp/* /var/tmp/*",
  #     "echo '=== FINAL DISK USAGE ==='",
  #     "df -h /",
  #     "du -sh /var/lib/docker 2>/dev/null || true",
  #   ]
  # }

  # Configure dnf to skip docs and extra locales BEFORE installing
  provisioner "shell" {
    inline = [
      "set -eux",
      "echo 'tsflags=nodocs' | sudo tee -a /etc/dnf/dnf.conf",
      "echo 'override_install_langs=en_US.UTF-8' | sudo tee -a /etc/dnf/dnf.conf",
    ]
  }

  # Install Jenkins + tooling
  provisioner "shell" {
    inline = [
      "set -eux",
      "sudo curl -sLo /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo dnf update -y",
      "sudo dnf install -y java-25-amazon-corretto git vim bind-utils docker amazon-ssm-agent jenkins",
      "sudo usermod -aG docker jenkins",
    ]
  }

  # Strip residual docs/locales, clean caches, zero free space
  provisioner "shell" {
    inline = [
      "set -eux",
      "sudo rm -rf /usr/share/man/* /usr/share/info/* /usr/share/doc/* || true",
      "sudo find /usr/lib/locale -mindepth 1 -maxdepth 1 ! -name 'C.utf8' ! -name 'en_US.utf8' -exec rm -rf {} + || true",
      "sudo dnf clean all",
      "sudo rm -rf /var/cache/dnf /var/cache/yum /tmp/* /var/tmp/*",
      "sudo journalctl --vacuum-size=0 || true",
      "sudo rm -rf /var/log/*.log /var/log/*.gz || true",
      "sudo dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true; sudo rm -f /EMPTY; sync",
      "echo '=== FINAL DISK USAGE ==='",
      "df -h /",
    ]
  }
}
