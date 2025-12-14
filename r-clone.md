Here is a step-by-step guide to configuring and using `rclone` to transfer files from your Linux server to an S3 bucket.

### 1\. Install Rclone

The easiest way to install rclone on Linux is via their official install script.

```bash
sudo -v ; curl https://rclone.org/install.sh | sudo bash
```

### 2\. Configure the Remote Connection

You need to tell rclone how to talk to your S3 bucket.

1.  Run the configuration command:
    ```bash
    rclone config
    ```
2.  Type **`n`** for "New remote".
3.  **Name the remote** (e.g., `remote-s3`).
4.  **Type of storage:** You will see a long list. Type `s3` or find "Amazon S3 Compliant Storage" and enter the corresponding number.
5.  **Provider:** Choose your provider. If using AWS, choose `AWS` (usually option 1). If you are using DigitalOcean Spaces, Minio, or Wasabi, choose those specific options.
6.  **Credentials:**
      * **access\_key\_id:** Paste your AWS Access Key ID.
      * **secret\_access\_key:** Paste your AWS Secret Access Key.
7.  **Region:** Choose the region where your bucket is located (e.g., `us-east-1`).
8.  **ACL / Storage Class:** You can generally leave these blank (press Enter) to use defaults unless you have specific requirements.
9.  **Advanced Config:** Type `n` to skip.
10. **Review:** It will show you a summary. Type `y` to confirm and then `q` to quit the config menu.

### 3\. Verify the Connection

Test if rclone can see your buckets.

```bash
# List all buckets in the remote
rclone lsd remote-s3:
```

*Note: The colon `:` at the end is required to indicate a remote.*

### 4\. Basic Commands

Rclone syntax is usually `rclone [command] [source] [destination]`.

#### A. Copying Files (Safe)

Use `copy` to move files from your server to S3. This will **add** new files to S3 but will **not delete** anything from S3 if it's missing on your server.

```bash
# Copy a single file
rclone copy /path/to/local/file.txt remote-s3:my-bucket-name/folder/

# Copy an entire directory
rclone copy /path/to/local/folder remote-s3:my-bucket-name/folder
```

#### B. Syncing Files (Mirroring - Use Caution)

Use `sync` to make the destination (S3) look *exactly* like the source (Linux server). **This deletes files on S3** if they do not exist on your local server.

```bash
# WARNING: This deletes data in the bucket that isn't on the local server
rclone sync /path/to/local/folder remote-s3:my-bucket-name/folder
```

> **Tip:** Always use the `--dry-run` flag first to see what rclone is going to do without actually doing it.
>
> ```bash
> rclone sync /home/user/data remote-s3:backup-bucket --dry-run
> ```

### 5\. Useful Flags

  * **`-P` or `--progress`:** Shows a progress bar for the transfer.
  * **`--transfers=N`:** Controls how many files are copied in parallel (default is 4). Increasing this can speed up transfers of many small files.
  * **`--bandwidth-limit=X`:** Limits bandwidth usage (e.g., `5M` for 5 Megabytes/s) to prevent choking your server's network.

-----

### Example Workflow

If you want to back up a database dump to a bucket named `production-backups`:

```bash
rclone copy /var/backups/db.sql remote-s3:production-backups/2023-10-27/ -P
```

**Would you like me to help you write a cron script to automate this backup process daily?**