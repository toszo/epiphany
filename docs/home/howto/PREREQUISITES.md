## Run Epicli from Docker image

There are 2 ways to get the image, build it locally yourself or pull it from the Epiphany docker registry.

### Build Epicli image locally

1. Install the following dependencies:

    - Python 3.7
    - PIP
    - Docker

2. Install the following Python dependencies using PIP:

    ```bash
    pip install wheel setuptools twine
    ```

3. Open a terminal in `/core/src/epicli` and run:

    On Linux/Mac:

    ```bash
    ./build-docker.sh debian|alpine
    ```

    On windows:

    ```bash
    ./build-docker.bat debian|alpine
    ```

*Note: Use the debian or alpine flag to indicate which base image you want to use for the Epicli container.*
  
### Pull Epicli image from the registry

```bash
docker pull epiphanyplatform/epicli:TAG
```

*Check [here](https://cloud.docker.com/u/epiphanyplatform/repository/docker/epiphanyplatform/epicli) for the available tags.*

### Running the Epicli image

To run the image:

Locally build:

```bash
docker run -it -v LOCAL_DIR:/shared --rm epicli
```

Pulled:

```bash
docker run -it -v LOCAL_DIR:/shared --rm epiphanyplatform/epicli:TAG
```

*Check [here](https://cloud.docker.com/u/epiphanyplatform/repository/docker/epiphanyplatform/epicli) for the available tags.*

Where `LOCAL_DIR` should be replaced with the local path to the directory for Epicli input (SSH keys, data yamls) and output (logs, build states).

## Run Epicli directly from OS

*Note: Epicli will only run on Lixux or MacOS and not on Windows. This is because Ansible at this point in time does not work on Windows.*

*Note: You might want to consider installing Epicli in a virtual python enviroment. More information can be found [here](https://packaging.python.org/guides/installing-using-pip-and-virtual-environments/).*

1. To be able to run the Epicli from your local OS you have to install:

    - Python 3.7
    - PIP

2. Install the following Python dependencies (in your virtual environment) using PIP:

    ```bash
    pip install wheel setuptools twine
    ```

3. Open a terminal in `/core/src/epicli` and run the following to build the Epicli wheel:

    ```bash
    ./build-wheel.sh
    ```

4. Install the Epicli wheel:

    ```bash
    pip install dist/epicli-VERSION-py3-none-any.whl
    ```

5. Verify the Epicli installation:

    ```bash
    epicli --version
    ```

    This should return the version of the CLI deployed.

Now you can use Epicli directly on your machine.

## Epicli development

For setting up en Epicli development environment please refer to this dedicated document [here.](./../DEVELOPMENT.md)

## Important notes

### Note for Windows users

- Watch out for the line endings conversion. By default Git for Windows sets `core.autocrlf=true`. Mounting such files with Docker results in `^M` end-of-line character in the config files.
Use: [Checkout as-is, commit Unix-style](https://stackoverflow.com/questions/10418975/how-to-change-line-ending-settings) (`core.autocrlf=input`) or Checkout as-is, commit as-is (`core.autocrlf=false`). Be sure to use a text editor that can work with Unix line endings (e.g. Notepad++).

- Remember to allow Docker Desktop to mount drives in Settings -> Shared Drives

- Escape your paths properly:

  - Powershell example:
  ```bash
  docker run -it -v C:\Users\USERNAME\git\epiphany:/epiphany --rm epiphany-dev:
  ```
  - Git-Bash example:
  ```bash
  winpty docker run -it -v C:\\Users\\USERNAME\\git\\epiphany:/epiphany --rm epiphany-dev
  ```

- Mounting NTFS disk folders in a linux based image causes permission issues with SSH keys. When running either the development or deploy image:

1. Copy the certs on the image:

    ```bash
    mkdir -p ~/.ssh/epiphany-operations/
    cp /epiphany/core/ssh/id_rsa* ~/.ssh/epiphany-operations/
    ```
2. Set the propper permission on the certs:

    ```bash
    chmod 400 ~/.ssh/epiphany-operations/id_rsa*
    ```

### Note about proxies

To run Epicli from behind a proxy, enviroment variables need to be set.

When running directly from OS or from a development container (upper and lowercase are needed because of an issue with the Ansible dependency):

  ```bash
  export http_proxy="http://PROXY_SERVER:PORT"
  export https_proxy="https://PROXY_SERVER:PORT"
  export HTTP_PROXY="http://PROXY_SERVER:PORT"
  export HTTPS_PROXY="https://PROXY_SERVER:PORT"
  ```

Or when running from a Docker image (upper and lowercase are needed because of an issue with the Ansible dependency):

  ```bash
  docker run -it -v POSSIBLE_MOUNTS... -e HTTP_PROXY=http://PROXY_SERVER:PORT -e HTTPS_PROXY=http://PROXY_SERVER:PORT http_proxy=http://PROXY_SERVER:PORT -e https_proxy=http://PROXY_SERVER:PORT --rm IMAGE_NAME
  ```

### Note about custom CA certificates

In some cases it might be that a company uses custom CA certificates for providing secure connections. To use these with Epicli you can do the following:

### Note about PostgreSQL preflight check

This reffers only to CentOS/Red Hat installations.

To prevent installation failure of PostgreSQL 10 server we are checking in preflight mode we are checking if previous 
installation has been installed from PostgreSQL official repository. If this has been installed from Software Collections
this will make Epiphany deployment fail in preflight mode. For more details please refer to [How to migrate from PostgreSQL installed from Software Collections to installed from PostgreSQL repository](./DATABASES.md#how-to-migrate-from-postgresql-installed-from-software-collections-to-installed-from-postgresql-repository)


#### Devcontainer

Before building the VSCode devcontainer place the *.crt file here: `/epiphany/core/src/epicli/.devcontainer/cert/`. Then the certificate will be included and configured during the build process. After that no additional configuration should be needed.

#### MacOS

Install the certiciate in your keychain as described [here](https://www.sslsupportdesk.com/how-to-import-a-certificate-into-mac-os/).

#### Epicli container or Debian based OS

If you are running Epicli from one of the prebuild containers or a Debian based OS directly you can do the following to install the certificate:

  ```bash
  cp ./path/to/cert.crt /usr/local/share/ca-certificates/
  chmod 644 /usr/local/share/ca-certificates/cert.crt
  update-ca-certificates
  ```

*Note: Configuring the CA cert on the prebuild container only works on the `Debian` based ones and NOT on `Alpine` based.*
