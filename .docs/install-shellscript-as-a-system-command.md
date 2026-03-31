# Install shell script as a system command

## Step-by-Step: Install `your-shell-script.sh` as a system command

### 1. **Make the Script Executable**

```bash
chmod +x your-shell-script.sh
```

### 2. **Move It to a Directory in Your PATH**

A typical location is `/usr/local/bin`, which is meant for custom scripts:

```bash
sudo mv your-shell-script.sh /usr/local/bin/your-shell-script
```

> You’re renaming it to `your-shell-script` (dropping the `.sh`) so you can run it like: `your-shell-script encrypt ...`

### 3. **Verify It's in Your PATH**

Run:

```bash
which your-shell-script
```

You should see:

```bash
/usr/local/bin/your-shell-script
```
---

## Step-by-Step: Install `gpgfy.sh` as a system command

### 1. **Make the Script Executable**

```bash
chmod +x gpgfy.sh
```

### 2. **Move It to a Directory in Your PATH**

A typical location is `/usr/local/bin`, which is meant for custom scripts:

```bash
sudo mv gpgfy.sh /usr/local/bin/gpgfy
```

> You’re renaming it to `gpgfy` (dropping the `.sh`) so you can run it like: `gpgfy encrypt ...`

### 3. **Verify It's in Your PATH**

Run:

```bash
which gpgfy
```

You should see:

```bash
/usr/local/bin/gpgfy
```

### 4. **Test It**

Try:

```bash
gpgfy
gpgfy encrypt secrets.txt recipient@example.com
gpgfy decrypt secrets.txt.asymmetric.gpg
```

You should see the usage output.

---

