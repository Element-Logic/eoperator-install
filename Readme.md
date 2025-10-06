# 🧰 eOperator Tentacle Installer

This repository contains a helper script for installing and configuring an **Octopus Tentacle** on Ubuntu  
It automates most of the setup needed for connecting a server to Octopus Deploy (Polling Tentacle).

---

## 📦 Prerequisites

- Ubuntu 
- Internet access to `https://elementlogic.octopus.app/`  
- A valid **Octopus API key** (created from your Octopus user profile)

---

## 🚀 Installation Steps

### 1️⃣ Download or clone this repository

If using `git`:
```bash
git clone https://github.com/Element-Logic/eoperator-install.git
cd eoperator-install
```


### 2️⃣ Make the script executable
```bash
chmod +x install-tentacle.sh
```

### 3️⃣ Edit the .env file
What to change:
- **OCTOPUS_API_KEY** → Paste your personal API key from Octopus Deploy → User Profile → API keys.
- **MACHINE_NAME** → Must be unique per machine and follows the naming format: Project number - center name - Environment

```bash
OCTOPUS_API_KEY="API-PASTE_YOUR_KEY_HERE"
MACHINE_NAME="000 - Test Ubuntu Server - Test"
```

### 4️⃣ Run the installer
```bash
./install-tentacle.sh
```


### ✅ Verification

After the script finishes:

1. Go to **Octopus Deploy → Infrastructure → Deployment targets**
2. Confirm that your machine:
   - ✅ Appears in the list  
   - 📝 Has the correct **name**  
   - 🧠 Has the correct tags **roles** (`eOperator`, `ubuntu`, `Production`)  
   - 💚 Shows as **Healthy**

You can also check the local Tentacle service:

```bash
sudo Tentacle list-instances
sudo systemctl status Tentacle
```


📄 License
Internal use only. © Element Logic