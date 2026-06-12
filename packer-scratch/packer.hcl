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

# Worker/build instance base (official AL2023 minimal arm64)
data "amazon-ami" "al2023_arm64" {
  filters = {
    name                = "al2023-ami-minimal-*-arm64"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.region
}

source "amazon-ebssurrogate" "jenkins" {
  region        = var.region
  instance_type = "t4g.small"
  source_ami    = data.amazon-ami.al2023_arm64.id
  ssh_username  = "ec2-user"

  # Surrogate volume -> becomes the new AMI root
  launch_block_device_mappings {
    device_name           = "/dev/xvdf"
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
  }

  ami_name                = "jenkins-ami-{{timestamp}}"
  ami_description         = "Jenkins on AL2023 arm64, built from scratch via ebssurrogate"
  ami_virtualization_type = "hvm"
  ami_architecture        = "arm64"
  boot_mode               = "uefi"

  ami_root_device {
    source_device_name    = "/dev/xvdf"
    device_name           = "/dev/xvda"
    delete_on_termination = true
    volume_size           = 8
    volume_type           = "gp3"
  }

  tags = {
    Name    = "jenkins-custom-ami"
    Builder = "packer"
  }
}

build {
  sources = ["source.amazon-ebssurrogate.jenkins"]

  # Step 1: GPT partition the surrogate disk (EFI + root)
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "DISK=/dev/xvdf",
      "sudo dnf install -y gdisk dosfstools xfsprogs",
      "sudo sgdisk --zap-all $DISK",
      "sudo sgdisk -n1:0:+200M -t1:EF00 -c1:EFI $DISK",
      "sudo sgdisk -n2:0:0     -t2:8300 -c2:root $DISK",
      "sudo partprobe $DISK",
      "sleep 3",
      "sudo mkfs.fat -F32 ${DISK}1",
      "sudo mkfs.xfs -f ${DISK}2",
    ]
  }

  # Step 2: Mount target + bind pseudo-filesystems
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "DISK=/dev/xvdf",
      "sudo mkdir -p /mnt/target",
      "sudo mount ${DISK}2 /mnt/target",
      "sudo mkdir -p /mnt/target/boot/efi",
      "sudo mount ${DISK}1 /mnt/target/boot/efi",
      "sudo mkdir -p /mnt/target/{proc,sys,dev,dev/pts,run,etc}",
      "sudo mount -t proc   proc   /mnt/target/proc",
      "sudo mount -t sysfs  sysfs  /mnt/target/sys",
      "sudo mount --bind /dev     /mnt/target/dev",
      "sudo mount --bind /dev/pts /mnt/target/dev/pts",
      "sudo mount -t tmpfs tmpfs  /mnt/target/run",
      "sudo cp /etc/resolv.conf /mnt/target/etc/resolv.conf",
    ]
  }

  # Step 3: Bootstrap OS into the root jail (arm64 bootloader packages)
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo dnf -y --installroot=/mnt/target --releasever=2023 install \\",
      "  @core system-release amazon-linux-repo-s3 \\",
      "  kernel kernel-modules dracut grub2-tools grub2-tools-minimal \\",
      "  grub2-efi-aa64 grub2-efi-aa64-modules shim-aa64 efibootmgr \\",
      "  systemd cloud-init cloud-utils-growpart openssh-server \\",
      "  passwd shadow-utils sudo chrony selinux-policy selinux-policy-targeted \\",
      "  policycoreutils amazon-ec2-net-utils xfsprogs dosfstools \\",
      "  iproute audit rng-tools NetworkManager",
    ]
  }

  # Step 4: fstab by UUID, GRUB EFI (arm64), initramfs, base services
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "DISK=/dev/xvdf",
      "ROOT_UUID=$(sudo blkid -s UUID -o value ${DISK}2)",
      "EFI_UUID=$(sudo blkid -s UUID -o value ${DISK}1)",
      "printf 'UUID=%s / xfs defaults,noatime 0 1\\n' \"$ROOT_UUID\" | sudo tee /mnt/target/etc/fstab",
      "printf 'UUID=%s /boot/efi vfat defaults,uid=0,gid=0,umask=0077,shortname=winnt 0 2\\n' \"$EFI_UUID\" | sudo tee -a /mnt/target/etc/fstab",

      "echo \"GRUB_CMDLINE_LINUX=\\\"console=tty0 console=ttyS0,115200n8 root=UUID=$ROOT_UUID\\\"\" | sudo tee /mnt/target/etc/default/grub",
      "echo 'GRUB_TIMEOUT=1'    | sudo tee -a /mnt/target/etc/default/grub",
      "echo 'GRUB_TERMINAL=\"serial console\"' | sudo tee -a /mnt/target/etc/default/grub",

      "sudo chroot /mnt/target grub2-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=AL2023 --removable --recheck",
      "sudo chroot /mnt/target grub2-mkconfig -o /boot/grub2/grub.cfg",

      "KVER=$(sudo chroot /mnt/target rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\\n' | tail -1)",
      "sudo chroot /mnt/target dracut --force --kver $KVER --add-drivers 'nvme ena' --filesystems xfs /boot/initramfs-$KVER.img",

      "sudo chroot /mnt/target systemctl enable sshd chronyd NetworkManager cloud-init-local cloud-init cloud-config cloud-final",
    ]
  }

  # Step 5: cloud-init defaults + SELinux relabel
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo tee /mnt/target/etc/cloud/cloud.cfg.d/10-ec2.cfg >/dev/null <<'EOF'",
      "system_info:",
      "  default_user:",
      "    name: ec2-user",
      "    sudo: ['ALL=(ALL) NOPASSWD:ALL']",
      "    groups: [wheel, docker]",
      "    shell: /bin/bash",
      "growpart:",
      "  mode: auto",
      "resize_rootfs: true",
      "EOF",
      "sudo touch /mnt/target/.autorelabel",
    ]
  }

  # Step 6: Jenkins + tooling, installed INTO the chroot
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      # repo + key go inside the target rootfs
      "sudo curl -sLo /mnt/target/etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo chroot /mnt/target rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo dnf -y --installroot=/mnt/target --releasever=2023 install \\",
      "  java-25-amazon-corretto git vim bind-utils docker amazon-ssm-agent jenkins",
      # docker group exists once docker is installed; add jenkins to it in-chroot
      "sudo chroot /mnt/target usermod -aG docker jenkins",
      "sudo chroot /mnt/target systemctl enable docker amazon-ssm-agent jenkins",
    ]
  }

  # Step 7: Clean, zero free space, unmount
  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "sudo dnf -y --installroot=/mnt/target clean all",
      "sudo rm -rf /mnt/target/var/cache/dnf /mnt/target/tmp/* /mnt/target/var/tmp/*",
      "sudo chroot /mnt/target journalctl --vacuum-size=0 || true",
      "sudo rm -f /mnt/target/etc/resolv.conf",
      "sudo dd if=/dev/zero of=/mnt/target/ZERO bs=1M 2>/dev/null || true; sudo rm -f /mnt/target/ZERO; sync",
      "sudo umount /mnt/target/dev/pts /mnt/target/dev /mnt/target/proc /mnt/target/sys /mnt/target/run || true",
      "sudo umount /mnt/target/boot/efi",
      "sudo umount /mnt/target",
    ]
  }
}
