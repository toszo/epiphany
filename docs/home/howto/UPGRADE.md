## Upgrade

### Introduction

From Epicli 0.4.2 and up the CLI has the ability to perform upgrades on certain components on a cluster. The components it currently can upgrade and will add are:

- kubernetes (master and nodes): Upgrades Kubernetes starting from 1.11.5 to 1.17.4 currently used in Epiphany 0.4.2
- common: Upgrades all common configurations to match them to Epiphany 0.4.2
- repository: Adds the repository role needed for component installation in Epiphany 0.4.2
- image_registry: Adds the image_registry role needed for offline installation in Epiphany 0.4.2

*Note: The component upgrade takes the existing Ansible build output and based on that performs the upgrade of the currently supported components. If you need to upgrade your entire Epiphany cluster a **manual** upgrade of the input yaml is needed to the latest specification which then should be applied with `epicli apply...` after the offline upgrade which is described here.*

### Online upgrade

#### Online prerequisites

Your airgapped existing cluster should meet the following requirements:

1. The cluster machines/vm`s are connected by a network or virtual network of some sorts and can communicate which each other and have access to the internet:
2. The cluster machines/vm`s are **upgraded** to the following versions:
    - RedHat 7.6
    - CentOS 7.6
    - Ubuntu 18.04
3. The cluster machines/vm`s should be accessible through SSH with a set of SSH keys you provided and configured on each machine yourself.
4. A provisioning machine that:
    - Has access to the SSH keys
    - Has access to the build output from when the cluster was first created.
    - Is on the same network as your cluster machines
    - Has Epicli 0.4.2 or up running.
      *Note. To run Epicli check the [Prerequisites](./PREREQUISITES.md)*

#### Start the online upgrade

Start the upgrade with:

    ```shell
    epicli upgrade -b /buildoutput/
    ```

This will backup and upgrade the Ansible inventory in the provided build folder `/buildoutput/` which will be used to perform the upgrade of the components.

### Offline upgrade

#### Offline prerequisites

Your airgapped existing cluster should meet the following requirements:

1. The airgapped cluster machines/vm`s are connected by a network or virtual network of some sorts and can communicate which each other:
2. The airgapped cluster machines/vm`s are **upgraded** to the following versions:
    - RedHat 7.6
    - CentOS 7.6
    - Ubuntu 18.04
3. The airgapped cluster machines/vm`s should be accessible through SSH with a set of SSH keys you provided and configured on each machine yourself.
4. A requirements machine that:
    - Runs the same distribution as the airgapped cluster machines/vm`s (RedHat 7, CentOS 7, Ubuntu 18.04)
    - Has access to the internet.
5. A provisioning machine that:
    - Has access to the SSH keys
    - Has access to the build output from when the cluster was first created.
    - Is on the same network as your cluster machines
    - Has Epicli 0.4.2 or up running.
      *Note. To run Epicli check the [Prerequisites](./PREREQUISITES.md)*

#### Start the offline upgrade

To upgrade the cluster components run the following steps:

1. First we need to get the tooling to prepare the requirements for the upgrade. On the provisioning machine run:

    ```shell
    epicli prepare --os OS
    ```

    Where OS should be `centos-7`, `redhat-7`, `ubuntu-18.04`. This will create a directory called `prepare_scripts` with the following files inside:

    - download-requirements.sh
    - requirements.txt
    - skopeo_linux

2. The scripts in the `prepare_scripts` will be used to download all requirements. To do that copy the `prepare_scripts` folder over to the requirements machine and run the following command:

    ```shell
    download-requirements.sh /requirementsoutput/
    ```

    This will start downloading all requirements and put them in the `/requirementsoutput/` folder. Once run succesfully the `/requirementsoutput/` needs to be copied to the provisioning machine to be used later on.

3. Finally start the upgrade with:

    ```shell
    epicli upgrade -b /buildoutput/ --offline-requirements /requirementsoutput/
    ```

    This will backup and upgrade the Ansible inventory in the provided build folder `/buildoutput/` which will be used to perform the upgrade of the components. The `--offline-requirements` flag tells Epicli where to find the requirements folder (`/requirementsoutput/`) prepared in steps 1 and 2 which is needed for the offline upgrade.

### Additional parameters

The `epicli upgrade` command had an additional flag `--wait-for-pods`. When this flag is added, the Kubernetes upgrade will wait until all pods are in the **ready** state before proceding. This can be usefull when a zero downtime upgrade is required. **Note: that this can also cause the upgrade to hang indefinitely.**

## How to upgrade Kafka

### Kafka upgrade

No downtime upgrades are possible to achieve when upgrading Kafka, but before you start thinking about upgrading you have to think about your topics configuration. Kafka topics are distributed accross partitions with replication. Default value for replication is 3, it means each partition will be replicated to 3 brokers. You should remember to enable redundancy and keep **at least two replicas all the time**, it is important when upgrading Kafka cluser. When one of your Kafka nodes will be down during upgrade ZooKeeper will direct your producers and consumers to working instances - having replicated partitions on working nodes will ensure no downtime and no data loss work.

Upgrading Kafka could be different for every Kafka release, please refer to [Apache Kafka documentation](https://kafka.apache.org/documentation/#upgrade). Important point to remember during Kafka upgrade is the rule: **only one broker at the time** - to prevent downtime you should uprage you Kafka brokers one by one.

### ZooKeeper upgrade

ZooKeeper redundancy is also recommended, since service restart is required during upgrade - it can cause ZooKeeper unavailability. Having at **least two ZooKeeper services** in *ZooKeepers ensemble* you can upgrade one and then start with the rest **one by one**.

More detailed information about ZooKeeper you can find in  [ZooKeeper documentation](https://cwiki.apache.org/confluence/display/ZOOKEEPER).
