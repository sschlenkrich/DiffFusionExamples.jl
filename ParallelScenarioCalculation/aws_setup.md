# AWS Setup

This document contains some details and guidance on how to setup AWS EC2 machines.

## AWS Instances

Generate access token files:
  - DiffFusion-OH.perm

Small machine:
  - Name: DiffFusion-c6a-Oh
  - Region us-east-2, US East (Ohio)
  - Instance type: c6a.4xlarge (16 vCPU)
  - User: celery

Large machine
  - Name: DiffFusion-hpc68-Oh
  - Region us-east-2, US East (Ohio)
  - Instance type: hpc6a (96 vCPU, no hyper threading)
  - User: celery


## User Setup and Login

Create user and set `bash` as default shell.

```
sudo useradd -ms /bin/bash celery
```

Set a password for user via shell.

```
echo "celery:[a_secret_password]" | sudo chpasswd
```

Allow `sudo` command for new user.

```
sudo adduser celery sudo
```

Allowing password-based login with Ubuntu is a bit more tricky. Update `/etc/ssh/sshd_config` as follows:

```
sudo vim /etc/ssh/sshd_config
```

Edit

```
PasswordAuthentication no
Match User celery
    PasswordAuthentication yes
Match all
```

Then run `sudo systemctl restart ssh` to activate the changes.

For reference, see [here](https://askubuntu.com/questions/1290454/ssh-with-pubkey).

## Tools and Software

If you want to clone from a private GitHub repo then you need to configure access to the repository. Access can be managed via a [Personal Access Token (PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

Create a file with name `set_token.sh` and content:

```
export GH_ACCESS_TOKEN=XYZ
 ```

Here, `XYZ` is to be replaced with the actual PAT.

Then you can clone a private repo via

```
git clone https://$GH_ACCESS_TOKEN@github.com/[path_to_repo]

```
