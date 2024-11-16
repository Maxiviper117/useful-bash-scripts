## Fetch and Execute Scripts Using curl

To download and execute a specific bash script from this repository, use the `curl` command. This allows you to run scripts directly without manually downloading them first. Below is an example of how to do this:

**Warning**: Executing scripts directly from the internet can be risky. Ensure you trust the source and understand what the script does before running it.

### Example Command

To fetch and execute the `userManager.sh` script, run the following command in your terminal:

```bash
curl -s https://raw.githubusercontent.com/Maxiviper117/useful-bash-scripts/src/user-management/userManager.sh | bash
```

### Command Breakdown
- `curl -s`: Fetches the script silently without showing progress.
- `https://raw.githubusercontent.com/.../userManager.sh`: The URL where the script is hosted.
- `| bash`: Pipes the fetched script directly to the bash shell for execution.

Replace `userManager.sh` with the desired script name to run other scripts from this repository.

## Using Docker to Safely Test Commands

To safely test the commands in an isolated environment, you can use Docker. Follow these steps to set up and use a Docker container:

### Step 1: Build the Docker Image

Ensure you have a `Dockerfile` in the root of your project. Run the following command to build the Docker image:

```bash
docker build -t ubuntu-custom .
```

### Step 2: Use Docker Compose

Ensure your `docker-compose.yml` is configured correctly. You can start the container using Docker Compose with the following command:

```bash
docker-compose up -d
```

This will create and start the container defined in your `docker-compose.yml` file.

### Step 3: Access the Container

To access the container's shell, use the following command:

```bash
docker exec -it ubuntu_container bash
```

You can now safely test your scripts within the container environment.