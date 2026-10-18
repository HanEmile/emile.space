(meta
  (tag "blog" "lisp")
  (published "2024-05-11")
  (modified "2026-09-22")
  (author "Emile")
  (info "tag" "published")
)

# lampadas

The NAS

(toc)

## Setup

motherboard: Asrock n100m
ram: idk.
data drives: 1TB Evo 970 + 1TB Evo 960 pro
system drive: 128GB Intenso

```
sda (1TB SSD)
  sda1
    luks
      btrfs raid1 (data)
```

```
sdb (1TB SSD)
  sdb1
    luks
      btrfs raid1 (data)
```

```
sdc (128GB SSD)
  sdc1
    btrfs (root)
  sdc2
    fat32 (boot)
```


## Installation

### partitions

#### system drive

```
parted --script --align optimal /dev/sdc -- mklabel gpt mkpart root 512MB 100% mkpart ESP fat32 1MB 512MB set 2 esp on
```

#### data drives

```
parted --script --align optimal /dev/sda -- mklabel gpt mkpart root 512MB 100%
parted --script --align optimal /dev/sdb -- mklabel gpt mkpart root 512MB 100%
```

### luks

```
curl -O http://192.168.1.102:8080/lampadas_luks_key
```

#### system drive

```
cat lampadas_luks_key | cryptsetup luksFormat /dev/sdc1
cat lampadas_luks_key | cryptsetup luksOpen /dev/sdc1 luksroot1
```

#### data drives

```
cat lampadas_luks_key | cryptsetup luksFormat /dev/sda1
cat lampadas_luks_key | cryptsetup luksOpen /dev/sda1 luksdata1
```

```
cat lampadas_luks_key | cryptsetup luksFormat /dev/sdb1
cat lampadas_luks_key | cryptsetup luksOpen /dev/sdb1 luksdata2
```

### filesystems

#### system drive

```
mkfs.btrfs -L root1 /dev/mapper/luksroot1
mkdir -p /mnt
mount /dev/mapper/luksroot1 /mnt
```

```
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/nix
umount /mnt
```

```
mkdir /mnt/{home,nix}
mount UUID=$(btrfs fi show | grep -Eo "[0-9a-z-]{16,}") -o compress=zstd,subvol=root /mnt
mount UUID=$(btrfs fi show | grep -Eo "[0-9a-z-]{16,}") -o compress=zstd,subvol=home /mnt/home
mount UUID=$(btrfs fi show | grep -Eo "[0-9a-z-]{16,}") -o compress=zstd,noatime,subvol=nix/mnt/nix
```

```
mkfs.fat -F 32 -n boot /dev/sdc2
```

#### data drives

create the btrfs filesystem on the luks filesystem:

```
mkfs.btrfs -L data1 /dev/mapper/luksdata1
mkfs.btrfs -L data2 /dev/mapper/luksdata2
mkdir -p /mnt/data
mount /dev/mapper/luksdata1 /mnt/data
```

add the second device (-f, as we've already got btrfs on the second drive):

```
btrfs device add -f /dev/mapper/luksdata2 /mnt/data
```

balance the raid1 (-dconvert converts data chunks, -mconvert converts metadata chunks)

```
btrfs balance start -dconvert=raid1 -mconvert=raid1 /mnt/data
```

### mount stuff

```
mkdir /mnt/boot
mount -o umask=077 /dev/disk/by-label/boot /mnt/boot
```

### nixos install

```
nixos-generate-config --root /mnt
cd /etc/nixos
mv configuration.nix config_orig.nix
curl -O http://192.168.1.102:8080/configuration.nix
```

Generate a host key for the initrd ssh session allowing us to enter the luks
password via ssh

```
ssh-keygen -t ed25519 -N "" -f initrd_ssh_host_key_ed25519
cp initrd_ssh_host_key_ed25519 /mnt
```

```
nixos-install
```

# Troubleshooting

boot into a nixos installer image

open the luks

```
curl -O http://192.168.1.102:8080/lampadas_luks_key
cat lampadas_luks_key | cryptsetup luksOpen /dev/sda1 luksroot1
cat lampadas_luks_key | cryptsetup luksOpen /dev/sdb1 luksroot2
```

figure out the uuid using `btrfs fi show` and insert it at the beginning of the
search term used in the grep below in order to mount the drives:

```
mkdir /mnt/{home,nix}
mount UUID=$(btrfs fi show | grep -Eo "c9[0-9a-z-]{16,}") -o compress=zstd,subvol=root /mnt
mount UUID=$(btrfs fi show | grep -Eo "c9[0-9a-z-]{16,}") -o compress=zstd,subvol=home /mnt/home
mount UUID=$(btrfs fi show | grep -Eo "c9[0-9a-z-]{16,}") -o compress=zstd,noatime,subvol=nix /mnt/nix
```

```
mount /dev/disk/by-label/boot /mnt/boot
```

# Nix foo

```
# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ pkgs, ... }:

let 
  emile_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPZi43zHEsoWaQomLGaftPE5k0RqVrZyiTtGqZlpWsew emile@caladan"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEzLZ56SEgwZZ0OusTdSDDhpMlxSg1zPNdRLuxKOfrR5 emile@chusuk"
];
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelParams = [ "ip=dhcp" ];
    initrd = {
      availableKernelModules = [ "r8169" ];
      systemd.users.root.shell = "/bin/cryptsetup-askpass";
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 22;
          hostKeys = ["/initrd_ssh_host_key_ed25519"];
          authorizedKeys = emile_keys;
        };
        postCommands = ''
          echo 'cryptsetup-askpass' > /root/.profile
        '';
      };
    };
  };

  fileSystems = {
    "/".options = ["compress=zstd"];
    "/home".options = ["compress=zstd"];
    "/nix".options = ["compress=zstd" "noatime"];
  };

  networking = {
    hostName = "lampadas";
    firewall.enable = true;
  };

  time.timeZone = "Europe/Berlin";

  powerManagement = {
    powertop.enable = true;
    scsiLinkPolicy = "med_power_with_dipm";
  };

  users = {
    mutableUsers = false;
    users = {
      root = {
        hashedPassword = "";
        openssh.authorizedKeys.keys = emile_keys;
      };
      emile = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = emile_keys;
      };
    };
  };

  environment.systemPackages = with pkgs; [ vim tailscale ];

  programs.mosh.enable = true;

  services = {
    # traffic metrics
    vnstat.enable = true;

    # ssh access
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    # VPN
    tailscale.enable = true;

    # filesystem stuff
    btrfs = {
      autoScrub.enable = true;
      autoScrub.interval = "weekly";
    };

    # metric exporters
    prometheus.exporters = {
      node.enable = true;
      systemd.enable = true;
      smartctl.enable = true;
    };

    # shares
    samba = {
      enable = true;
      openFirewall = true;
      securityType = "user";
      extraConfig = ''
        workgroup = WORKGROUP
        server string = lampadas
        netbios name = lampadas
        security = user
        hosts allow = 100.64.0.0/255.192.0.0, 127.0.0.1/255.0.0.0, ::1, 192.168.0.
        hosts deny = 0.0.0.0/0
        guest account = nobody
        map to guest = bad user
        load printers = no
        server min protocol = SMB3
        server smb encrypt = required 

        read raw = Yes
        write raw = Yes
        socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
        min receivefile size = 16384
        use sendfile = true
        aio read size = 16384
        aio write size = 16384

        server multi channel support = yes
      '';
      shares = {
        public = {
          path = "/data/public";
          "browseable" = "yes";
          "read only" = "no";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "emile";
          "force group" = "users";
          "comment" = "public data";
        };
        private = {
          path = "/data/private";
          "browseable" = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
          "force user" = "emile";
          "force group" = "users";
          "comment" = "private data (no flags though)";
        };
        time_machine = {
          path = "/data/time_machine";
          "public" = "no";
          "writeable" = "yes";
          "valid users" = "emile";
          "force user" = "emile"; 
          "fruit:aapl" = "yes";
          "fruit:time machine" = "yes";

          # otherwise, copying on the server happens Server -> Client ->
          # Server (but only on macos)
          "fruit:copyfile" = "yes";

          "vfs objects" = "catia fruit streams_xattr";
          "comment" = "time machine backups";
        };
      };
    };
  };

  system = {
    stateVersion = "23.11";
    autoUpgrade.enable = true;
  };

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    settings = {
      auto-optimise-store = true;
    };
  };
}
```
