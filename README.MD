# Penumbra Full Node Setup

## Table of Contents
- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Setup Steps](#setup-steps)
  - [Basics](#basics)
  - [Deep Dive](#deep-dive)
    - [Full Node](#full-node---steps--details)
    - [Monitoring](#monitoring---steps--details)
- [Usage](#usage)
- [Improvements](#improvements)
- [References](#references)

## Introduction
We are trying to setup a fullnode for [penumbra](guide.penumbra.zone) to aim to make it function as validator.
I have tried to make use of config manager **ansible** & **docker** for this setup.
Setup has 2 main components. `monitoring` & actual `fullnode` setup on testnet.

## Prerequisites
- Ansible installed on your local machine
- A server(s) to deploy the Penumbra node & monitoring stacks.
- [read more ](https://guide.penumbra.zone/node/pd/requirements.html)about requirements that are specific to machine where penumbra nodes can run.

## Setup Steps
There has been a bit of learning that are not possibly be found in the official documentation when this is being written.
its necessery that none of these steps are missed and are in order when you setting this up, not following may cause the node being not up and running.

#### Basics
* Make sure you have an machine that follows the basic set of [requirements](https://guide.penumbra.zone/node/pd/requirements.html).
* We are using docker for this setup , so using ansible we make sure the docker is installed along with docker-network & volumes are pre-created.
* We mainly need 2 main services to setup full node : [cometBFT](https://github.com/cometbft/cometbft) & lets call it[ pd service aka penumbra](https://github.com/penumbra-zone/penumbra/).
* To support the need for database , we need to install postgres.
* Next for monitoring we are going with [grafana](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/) & [prometheus](https://prometheus.io/docs/prometheus/latest/installation/) & [alertManager](https://prometheus.io/docs/alerting/latest/alertmanager/) , which we will put up on the mainframe of monitoring.
* and then only then comes the other metrics agents/collectors for the docker installation and the host machine. [cAdvisor](https://github.com/google/cadvisor) & [node-exporter](https://github.com/prometheus/node_exporter)
* Last but not least, The grafana dashboards & rulings for now we can use the defaults which would be suffecient to gain visiblity.

### Diving Deep

#### Full Node - Steps & details

* We provision `roles/docker_base` : this creates following.
    *   Install docker dependecies & docker engines.
    *   Install docker itself.
    *   Create Docker network & volume (volume not used in this).
* We provision `roles/file_setup` : Copies files from the directory to ssh machine, they contain dockerfile that creates `penumbra` service init container & sql schema for cometbft service.
* We now provision `roles/postgres` : Creates postgres DB with docker & volume and user setup. including provision of the schema & users.
*  Now it comes to `roles/penumbra` : which creates following.
    * First docker image from the dockerfile you see at `./roles/file_setup/files` . along side the `node.json` & `init-volume.sh` & `pd-init.sh`, the last one is most important in this case, and perform.
    * We run the docker container with this newly built image called `penumbra_init_container_<>` , and performs following **important** tasks.
        * Runs within the container this command :
        ```sh    pd testnet --testnet-dir /penumbra-config/testnet_data join \
        --tendermint-p2p-bind 0.0.0.0:26656 \
        --tendermint-rpc-bind 0.0.0.0:26657 \
        $external_address_flag \
        $moniker_flag \
        "$PENUMBRA_BOOTSTRAP_URL";
        ``` 
        this create a file structure & default configs in the place `/penumbra-config/testnet_data` which is later used by other services.
        * this is about joining a testnet where `$PENUMBRA_BOOTSTRAP_URL` supplies with the target rpc URL of a testnet (e.g https://rpc.testnet.penumbra.zone/).
        * next most important config is archive URL, which we set to the container by `PENUMBRA_PD_ARCHIVE_URL` env variable. and is the value we find in the documentation [here](https://guide.penumbra.zone/node/pd/join-testnet.html#generating-configs).
        This downloads the minimum set of chain history to get it started with, and *its important to have them pulled, otherwise the `penumbra` service wont be able to start and may throw concensus key issue.*
        * makking sure the path `/<TESTNET_DIR>/node0/cometbft` (to be used by cometbft service) and `/<TESTNET_DIR>/node0/pd` (to be used by penumbra service) are set to correct permissions. so they can access their own set of paths correctly.
        * the permissions we set **as** user root to theier own set of users i find in their designeted Dockerfiles, since we create the container and run it as root. 
        * and we `Put up latest genesis file` from the testnet we are to join. **which often get overwritten in wrong way**, so its an important step.
        * Now we update the concensus key from cometbft config location to the `validator.toml` , at location `/pocli` (location is not important for otherservices for this file)
        and we update other necessery configs.
        * then we upload the validator toml to the chain, which required us to have our penumbra address present in the `pcli` config/db/keychain. (so you would notice we also imported the wallet from a pass-phrase)
        * and these - importing wallet, joining network are something are one off new installation tasks, and cannot be performed on existing one.
        * Default the validator is not enabled, so there is a option of privision to enable that and stake own vlaidator with some amount of penumbra to increase the prority bid, which can be passed from the enviuronment variable, and can be passed whenever ready on existing system.
    * Now that we are ready with configs of comebft, pd, testnet joining, importing penumbra address & importantly importing the archive history of the chain. we can get started with installing `penumbra` itself as a container.
        * running this isnt enough, but this exposes the rpc frontend. & grpc node and metrics in different ports.
        * its better
* Now its time to finally start `cometbft` from `roles/cometbft`. which will start sending the request towards the `penumbra` container. and as transactions pulled , they will store necessery details to the postgres.
    * a thing to note here, that this service makes use of every config we have within `<TESTNET_DIR>/node0/cometbft/config` (e.g genesis.json, config.toml, validator and other node keys)
* Now once you see everything is running fine, and the logs states so, you can check the status with [these](https://guide.penumbra.zone/node/pd/debugging.html) steps.


#### Monitoring - Steps & details
* Gather what needs to be monitored.
    * since we running on a VM, we need to monitor the host and its storage. (sicne the services are quite storage extensive)
    * we need to monitor docker engine and its resource usage at even in container levels.
    * we need to monitor the networks.
* To respond to the above (`roles/target`), 
    * we install `CAdvisor` to monitor the docker related resources.
    * we install `node-exporter` to gain visiblity about the host/node itself.
    * Both releases metrics endpoints which are something we can use as targets for prometheus.
* to monitor the services, we need to install `grafana` for visualizing, `prometheus` for storing metrics and serving them an option to query, `alert-manager` to process and manage alerts , which is done here `roles/observer/` we are installing with a set of default configs and dashboard that are found in official docs and repositories.
    * Now we modify them as per our need, e.g configure the targets of `cadvisor` and `node-exporter`
    * we modify the datasources and targets to place and scrape the metrics from the services such as cometBFT & penumbra & import relavent dashboards from the official repository.

##### NOTE: All the services are in public IP and port listening , which is something should be improved/changed.


## Usage

1. Clone the repository.
2. Navigate to `inventory/penumbra.yaml` file and **update** the host configs necessery.
    * by-default `monitoring_3` is used to install monitoting components (`grafana` & `prometheus` , `alert-manager`, along side agents: `cadvisor` & `node-expoerter`) & `fullnode_3` has monitoring agents with the cometbft and penumbra service with postgres-sql.
3. Update the `ansible.cfg` to update the ssh key location.
4. Checkout the hostsin `playbooks/run-penumbra.yaml` they are being installed to, incase you choose to name the hosts differently at  step 2, and update if necessery.
5. Make sure you update the secret `penumbra_wallet_phrase_secret` & in this file. (e.g `ansible-vault encrypt_string "<REDACTED> aunt orphan only mushroom cross answer art youth echo muffin slow ordinary liberty rally palm`) - use the genereted output.
6. Update the ncessery alert manager configs in this same file.
7. run to install only fullnode.
```sh
ansible-playbook -i inventory/penumbra.yaml playbooks/run-penumbra.yaml -t fullnode --ask-vault-pass
```
8. run to install only monitoring components.
```sh
ansible-playbook -i inventory/penumbra.yaml playbooks/run-penumbra.yaml -t monitoring --ask-vault-pass
```
9. **you can optionally install everything**, with just not specifying the tag.
```sh
ansible-playbook -i inventory/penumbra.yaml playbooks/run-penumbra.yaml --ask-vault-pass
```

#### Improvements
* The exposed ports needs to be checked and controlled as much possible.
* Even the metrics endpoint that are necessery to expose - to be exposeed within private network of subnets.
* Alerting to be improved with different set of metrics from nodes.
* Support integrating  Horcrux or tmkms, to support HA for block signing , it secures the validator private key by splitting it across multiple private signer nodes.
* Install the prom-agent to scrape metrics and use `remote-write` approach to prometheus instead of scraping over targets that are exposed.
* Take backups every 4 hours or so, depending on the activity for the data directory of the cometbft.
* Consider backing up the config files with secrets to vault where versioning supports to have them handy if necessery.
* Have more option to perform `pd` cli base commands in ansible with init-container based approach to perform logical migrations.

#### References
* https://github.com/cometbft/cometbft/blob/main/DOCKER/Dockerfile
* https://guide.penumbra.zone/node/pd.html
* https://github.com/penumbra-zone/penumbra/tree/main/deployments