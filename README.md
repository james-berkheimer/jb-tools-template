## LXC Deployment Instructions

1. **Download and extract the latest deployment bundle:**

   ```bash
   curl -L https://github.com/james-berkheimer/jb-tools-template/releases/latest/download/jb-tools-lxc.tar.gz | tar xz
   cd jb-tools-lxc
   ```

2. **Make sure scripts are executable:**

   ```bash
   chmod +x create.sh
   ```

3. **Copy and edit the environment configuration:**

   ```bash
   cp env-template env
   nano env
   ```

   Set your desired container ID, IP addresses, password, etc.

4. **Create the container:**

   ```bash
   sudo ./create.sh
   ```

   This will automatically:

   - Create the LXC container
   - Configure networking
   - Install Python and SSH
   - Set up a clean working environment
