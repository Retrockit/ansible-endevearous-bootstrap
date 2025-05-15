#!/bin/bash
#
# bootstrap-ansible.sh - Prepare Arch Linux system for Ansible playbooks
# =====================================================================

set -eo pipefail

echo "==> Bootstrapping Arch Linux system for Ansible execution"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Get the actual user who invoked sudo
ACTUAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
USER_HOME="/home/$ACTUAL_USER"

echo "==> Setting up environment for user: $ACTUAL_USER"

# Install uv as the user (not as root)
echo "==> Installing uv package manager for user $ACTUAL_USER"
su - "$ACTUAL_USER" -c "curl -LsSf https://astral.sh/uv/install.sh | sh"

# Add uv to user's PATH if not already there
if ! grep -q "\.local/bin" "$USER_HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
    echo "==> Added ~/.local/bin to PATH in .bashrc"
fi

# Create a virtual environment for Ansible
echo "==> Creating virtual environment for Ansible"
su - "$ACTUAL_USER" -c "mkdir -p $USER_HOME/.venvs"
su - "$ACTUAL_USER" -c "$USER_HOME/.local/bin/uv venv $USER_HOME/.venvs/ansible"

# Install ansible-core using correct uv tool install command
echo "==> Installing ansible-core using uv tool install"
su - "$ACTUAL_USER" -c "source $USER_HOME/.venvs/ansible/bin/activate && $USER_HOME/.local/bin/uv tool install ansible-core"

# Install required Ansible collections
echo "==> Installing required Ansible collections"
su - "$ACTUAL_USER" -c "source $USER_HOME/.venvs/ansible/bin/activate && ansible-galaxy collection install community.general"

# Clone the repository
echo "==> Cloning the ansible-endevearous-bootstrap repository"
if [ ! -d "$USER_HOME/ansible-endevearous-bootstrap" ]; then
    su - "$ACTUAL_USER" -c "git clone https://github.com/Retrockit/ansible-endevearous-bootstrap.git $USER_HOME/ansible-endevearous-bootstrap"
else
    echo "Repository already exists, updating"
    su - "$ACTUAL_USER" -c "cd $USER_HOME/ansible-endevearous-bootstrap && git pull"
fi

# Add convenience activation script that also changes to the correct directory
cat > "$USER_HOME/run-ansible-bootstrap.sh" << 'EOF'
#!/bin/bash
# This script activates Ansible and runs the bootstrap playbook

# Activate the Ansible environment
source "$HOME/.venvs/ansible/bin/activate"

# Set Ansible display preferences
export ANSIBLE_STDOUT_CALLBACK=yaml

# Change to the repository directory
cd "$HOME/ansible-endevearous-bootstrap"

# Print status
echo "Ansible environment activated in $PWD"
echo "Run your playbook with: ansible-playbook playbook.yml"
echo ""
echo "To run the default bootstrap playbook now, press Enter."
echo "To exit, press Ctrl+C"
read -r

# Run the playbook
ansible-playbook playbook.yml
EOF

chmod +x "$USER_HOME/run-ansible-bootstrap.sh"
chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/run-ansible-bootstrap.sh"

# Create a basic ansible.cfg file in the repo directory
if [ ! -f "$USER_HOME/ansible-endevearous-bootstrap/ansible.cfg" ]; then
    cat > "$USER_HOME/ansible-endevearous-bootstrap/ansible.cfg" << 'EOF'
[defaults]
inventory = ./inventories/local
stdout_callback = yaml
deprecation_warnings = False
host_key_checking = False
retry_files_enabled = False
EOF

    chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/ansible-endevearous-bootstrap/ansible.cfg"
    echo "==> Created ansible.cfg configuration file"
fi

# Create local inventory if it doesn't exist
mkdir -p "$USER_HOME/ansible-endevearous-bootstrap/inventories"
if [ ! -f "$USER_HOME/ansible-endevearous-bootstrap/inventories/local" ]; then
    cat > "$USER_HOME/ansible-endevearous-bootstrap/inventories/local" << EOF
[local]
localhost ansible_connection=local
EOF
    
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/ansible-endevearous-bootstrap/inventories"
    echo "==> Created local inventory file"
fi

echo "==> Bootstrap completed successfully!"
echo ""
echo "To run the Ansible playbook, execute:"
echo "  ~/run-ansible-bootstrap.sh"
echo ""
echo "This will activate the environment, change to the repository directory,"
echo "and provide the option to run the playbook immediately."
echo ""
echo "NOTE: You may need to log out and back in for PATH changes to take effect."
