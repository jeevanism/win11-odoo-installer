### 🚀 Accelerated Odoo Installer Script

This installer script **simplifies and accelerates** your Odoo setup by handling complex dependencies and configuration steps, making the entire installation process smooth and fast.

---

## ✨ Key Benefits

| Feature | Description |
| :--- | :--- |
| **Speed** | Utilizes the **`uv`** package manager, which is vastly superior to `pip` in speed, ensuring dependencies are installed significantly faster. |
| **Reliability (Odoo 16)** | Automatically overcomes the common **`libsass` build failure** by downloading and using a pre-built `libsass` wheel. |

---

## 🛠️ The Setup Process

The script guides you through the following streamlined workflow:

1.  **Version Selection:** You are prompted to select the **Odoo version** you wish to install.
2.  **Environment Setup:** The script automatically installs the **required Python version** and creates a dedicated **virtual environment** within your current directory.
3.  **Dependency Install:** It clones the correct `requirements.txt` file and uses `uv` to rapidly install all necessary packages.
4.  **Source Code:** It **clones only the selected Odoo branch** (avoiding a full, time-consuming repository clone).
5.  **Configuration:** It generates a basic, ready-to-use **`odoo.conf` starter file** for easy initial setup.

***Note:** PostgreSQL database installation and configuration must be handled separately.*

### Screenshots : 
![installation prompt](https://github.com/jeevanism/win11-odoo-installer/blob/main/assets/win_odoo_installer.gif)

![post-installation](https://github.com/jeevanism/win11-odoo-installer/blob/main/assets/post_install_msg.png)
![odoo-starting-up](https://github.com/jeevanism/win11-odoo-installer/blob/main/assets/post-install-2.png)