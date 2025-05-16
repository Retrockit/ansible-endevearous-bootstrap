#!/bin/bash
#
# bootstrap-ansible.sh - Prepare Arch/Endeavour Linux system for Ansible playbooks
# =============================================================================

set -eo pipefail

echo "==> Bootstrapping Endeavour OS system for Ansible execution"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Get the actual user who invoked sudo
ACTUAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
USER_HOME="/home/$ACTUAL_USER"

# Get the repository root directory (where this script is located)
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "==> Setting up environment for user: $ACTUAL_USER"
echo "==> Repository location: $REPO_DIR"

# Define user's local bin path
LOCAL_BIN_PATH="$USER_HOME/.local/bin"

# Install uv as the user (not as root)
echo "==> Installing uv package manager for user $ACTUAL_USER"
su - "$ACTUAL_USER" -c "curl -LsSf https://astral.sh/uv/install.sh | sh"

# Add uv to user's PATH for future sessions
if ! grep -q "\.local/bin" "$USER_HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.bashrc"
    echo "==> Added ~/.local/bin to PATH in .bashrc for future sessions"
fi

# First install Python using uv
echo "==> Installing Python 3.13.3 using uv"
su - "$ACTUAL_USER" -c "$LOCAL_BIN_PATH/uv python install 3.13.3"

# Get the full path to the installed Python
echo "==> Locating installed Python"
PYTHON_PATH=$(su - "$ACTUAL_USER" -c "$LOCAL_BIN_PATH/uv python executable 3.13.3")
echo "==> Using Python at: $PYTHON_PATH"

# Create a virtual environment for Ansible using the specific Python interpreter
echo "==> Creating virtual environment for Ansible with uv Python"
su - "$ACTUAL_USER" -c "mkdir -p $USER_HOME/.venvs"
su - "$ACTUAL_USER" -c "$LOCAL_BIN_PATH/uv venv --python $PYTHON_PATH $USER_HOME/.venvs/ansible"

# Use full path to install ansible-core
echo "==> Installing ansible-core using uv tool install"
su - "$ACTUAL_USER" -c "source $USER_HOME/.venvs/ansible/bin/activate && $LOCAL_BIN_PATH/uv tool install ansible-core"

# Use full path for ansible-galaxy
echo "==> Installing required Ansible collections"
su - "$ACTUAL_USER" -c "source $USER_HOME/.venvs/ansible/bin/activate && $USER_HOME/.venvs/ansible/bin/ansible-galaxy collection install community.general"

# Ensure local inventory exists
if [ ! -d "$REPO_DIR/inventories" ]; then
    echo "==> Creating inventories directory"
    mkdir -p "$REPO_DIR/inventories"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$REPO_DIR/inventories"
fi

if [ ! -f "$REPO_DIR/inventories/local" ]; then
    echo "==> Creating local inventory file"
    cat > "$REPO_DIR/inventories/local" << EOF
[local]
localhost ansible_connection=local
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$REPO_DIR/inventories/local"
fi

# Create ansible.cfg if it doesn't exist
if [ ! -f "$REPO_DIR/ansible.cfg" ]; then
    echo "==> Creating ansible.cfg configuration file"
    cat > "$REPO_DIR/ansible.cfg" << 'EOF'
[defaults]
inventory = ./inventories/local
stdout_callback = yaml
deprecation_warnings = False
host_key_checking = False
retry_files_enabled = False
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$REPO_DIR/ansible.cfg"
fi

# Create a run script that uses full paths
echo "==> Creating activation and run script"
cat > "$USER_HOME/run-ansible-bootstrap.sh" << EOF
#!/bin/bash
# This script activates Ansible and runs the bootstrap playbook

# Activate the Ansible environment
source "\$HOME/.venvs/ansible/bin/activate"

# Export the updated PATH for current session
export PATH="\$HOME/.local/bin:\$PATH"

# Set Ansible display preferences
export ANSIBLE_STDOUT_CALLBACK=yaml

# Change to the repository directory
cd "$REPO_DIR"

# Print status
echo "Ansible environment activated in \$PWD"
echo "Repository directory: $REPO_DIR"
echo "Using Python: \$(python --version)"
echo ""
echo "Available playbooks:"
find . -maxdepth 1 -name "*.yml" | sed 's|./||'
echo ""
echo "To run the main playbook (playbook.yml), press Enter."
echo "To exit, press Ctrl+C"
read -r

# Use full path to ansible-playbook
\$HOME/.venvs/ansible/bin/ansible-playbook playbook.yml
EOF

chmod +x "$USER_HOME/run-ansible-bootstrap.sh"
chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/run-ansible-bootstrap.sh"

# Create a direct execution script that doesn't require sourcing
echo "==> Creating direct execution script"
cat > "$USER_HOME/execute-ansible-bootstrap.sh" << EOF
#!/bin/bash
# This script activates Ansible and directly runs the bootstrap playbook

# Export the updated PATH for current session
export PATH="\$HOME/.local/bin:\$PATH"

# Change to the repository directory
cd "$REPO_DIR"

# Run with the full path to the ansible-playbook command
\$HOME/.venvs/ansible/bin/ansible-playbook playbook.yml
EOF

chmod +x "$USER_HOME/execute-ansible-bootstrap.sh"
chown "$ACTUAL_USER:$ACTUAL_USER" "$USER_HOME/execute-ansible-bootstrap.sh"

echo "==> Bootstrap completed successfully!"
echo ""
echo "You can run the playbook in two ways:"
echo ""
echo "1. Source the activation script (recommended):"
echo "   source ~/run-ansible-bootstrap.sh"
echo ""
echo "2. Run the direct execution script:"
echo "   ~/execute-ansible-bootstrap.sh"
echo ""
echo "The direct execution script can be run immediately without PATH issues."
