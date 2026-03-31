# Linux User Management Automation

Automates bulk user creation, group assignment, SSH key generation and sudo access from a CSV file.

## Features
- Bulk create users from a CSV file
- Auto-creates groups if they don't exist
- Generates ed25519 SSH key pairs per user
- Grants sudo access via /etc/sudoers.d
- Saves credentials securely (chmod 600)
- Full audit log of every action
- Create or delete individual users via CLI

## Usage
```bash
./user_manager.sh --csv              # process all users from CSV
./user_manager.sh --list             # list users and their status
./user_manager.sh --create bob devops yes   # create one user
./user_manager.sh --delete bob       # delete a user
./user_manager.sh --audit            # view audit log
```

## CSV Format
```csv
username,group,sudo,shell
alice,developers,no,/bin/bash
bob,devops,yes,/bin/bash
```

## Technologies
`bash` · `useradd` · `groupadd` · `ssh-keygen` · `sudoers` · `chpasswd` · `awk`

## Author
Shubham · [github.com/18shubham](https://github.com/18shubham)

Test Example:

<img width="646" height="448" alt="image" src="https://github.com/user-attachments/assets/34a1f345-6ddf-4347-a8ea-272c80719e65" />

