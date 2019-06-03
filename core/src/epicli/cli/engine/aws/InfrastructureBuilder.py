from cli.helpers.doc_list_helpers import select_first
from cli.helpers.data_loader import load_yaml_obj, types
from cli.helpers.config_merger import merge_with_defaults
from cli.engine.aws.APIProxy import APIProxy
from cli.helpers.Step import Step
from cli.helpers.doc_list_helpers import select_single, select_all


class InfrastructureBuilder(Step):
    def __init__(self, docs):
        super().__init__(__name__)
        self.cluster_model = select_single(docs, lambda x: x.kind == 'epiphany-cluster')
        self.cluster_name = self.cluster_model.specification.name.lower()
        self.docs = docs

    def run(self):
        infrastructure = []

        public_key_config = self.get_public_key()
        infrastructure.append(public_key_config)

        vpc_config = self.get_vpc_config()

        infrastructure.append(vpc_config)
        default_security_group = self.get_default_security_group_config(vpc_config)
        infrastructure.append(default_security_group)

        vpc_name = vpc_config.specification.name

        internet_gateway = self.get_internet_gateway(vpc_config.specification.name)
        infrastructure.append(internet_gateway)
        route_table = self.get_routing_table(vpc_name, internet_gateway.specification.name)
        infrastructure.append(route_table)

        efs_config = self.get_efs_config()
        subnet_index = 0

        for component_key, component_value in self.cluster_model.specification.components.items():
            if component_value['count'] < 1:
                continue
            subnet = select_first(infrastructure, lambda item: item.kind == 'infrastructure/subnet' and
                                  item.specification.cidr_block == component_value.subnet_address_pool)
            security_group = select_first(infrastructure, lambda item: item.kind == 'infrastructure/security-group' and
                                          item.specification.cidr_block == component_value.subnet_address_pool)

            if subnet is None:
                subnet = self.get_subnet(component_value, component_key, vpc_name)
                infrastructure.append(subnet)

                security_group = self.get_security_group(subnet, component_key, vpc_name)
                infrastructure.append(security_group)

                route_table_association = self.get_route_table_association(route_table.specification.name,
                                                                           subnet.specification.name, subnet_index)
                infrastructure.append(route_table_association)

            autoscaling_group = self.get_autoscaling_group(component_key, component_value,
                                                           subnet.specification.name)

            security_group.specification.rules += autoscaling_group.specification.security.rules

            launch_configuration = self.get_launch_configuration(autoscaling_group, component_key,
                                                                 security_group.specification.name)

            launch_configuration.specification.key_name = public_key_config.specification.name

            self.set_image_id_for_launch_configuration(self.cluster_model, self.docs, launch_configuration,
                                                       autoscaling_group)
            autoscaling_group.specification.launch_configuration = launch_configuration.specification.name

            if autoscaling_group.specification.mount_efs:
                self.efs_add_mount_target_config(efs_config, subnet.specification.name)

            infrastructure.append(autoscaling_group)
            infrastructure.append(launch_configuration)

        if self.has_efs_any_mounts(efs_config):
            infrastructure.append(efs_config)
            self.add_security_rules_inbound_efs(infrastructure, default_security_group)

        return infrastructure

    def get_vpc_config(self):
        vpc_config = self.get_config_or_default(self.docs, 'infrastructure/vpc')
        vpc_config.specification.address_pool = self.cluster_model.specification.cloud.vnet_address_pool
        vpc_config.specification.name = "aws-vpc-" + self.cluster_name
        return vpc_config

    def get_default_security_group_config(self, vpc_config):
        sg_config = self.get_config_or_default(self.docs, 'infrastructure/default-security-group')
        sg_config.specification.vpc_name = vpc_config.specification.name
        return sg_config

    def get_efs_config(self):
        efs_config = self.get_config_or_default(self.docs, 'infrastructure/efs-storage')
        efs_config.specification.token = "aws-efs-token-" + self.cluster_name
        efs_config.specification.name = "aws-efs-" + self.cluster_name
        return efs_config

    def get_autoscaling_group(self, component_key, component_value, subnet_name):
        autoscaling_group = self.get_virtual_machine(component_value, self.cluster_model, self.docs)
        autoscaling_group.specification.name = 'aws-asg-' + self.cluster_name + '-' + component_value.machine + '-' + component_key.lower()
        autoscaling_group.specification.count = component_value.count
        autoscaling_group.specification.subnet = subnet_name
        autoscaling_group.specification.tags.append({component_key: ''})
        autoscaling_group.specification.tags.append({'cluster_name': self.cluster_name})
        return autoscaling_group

    def get_launch_configuration(self, autoscaling_group, component_key, security_group_name):
        launch_configuration = self.get_config_or_default(self.docs, 'infrastructure/launch-configuration')
        launch_configuration.specification.name = 'aws-launch-config-' + self.cluster_name + '-' \
                                                  + component_key.lower()
        launch_configuration.specification.size = autoscaling_group.specification.size
        launch_configuration.specification.security_groups = [security_group_name]
        return launch_configuration

    def get_subnet(self, component_value, component_key, vpc_name):
        subnet = self.get_config_or_default(self.docs, 'infrastructure/subnet')
        subnet.specification.vpc_name = vpc_name
        subnet.specification.cidr_block = component_value.subnet_address_pool
        subnet.specification.name = 'aws-subnet-' + self.cluster_name + '-' + component_key
        return subnet

    def get_security_group(self, subnet, component_key, vpc_name):
        security_group = self.get_config_or_default(self.docs, 'infrastructure/security-group')
        security_group.specification.name = 'aws-security-group-' + self.cluster_name + '-' + component_key
        security_group.specification.vpc_name = vpc_name
        security_group.specification.cidr_block = subnet.specification.cidr_block
        return security_group

    def get_route_table_association(self, route_table_name, subnet_name, subnet_index):
        route_table_association = self.get_config_or_default(self.docs, 'infrastructure/route-table-association')
        route_table_association.specification.name = 'aws-route-association-' + self.cluster_name + '-' + str(subnet_index)
        route_table_association.specification.subnet_name = subnet_name
        route_table_association.specification.route_table_name = route_table_name
        return route_table_association

    def get_internet_gateway(self, vpc_name):
        internet_gateway = self.get_config_or_default(self.docs, 'infrastructure/internet-gateway')
        internet_gateway.specification.name = 'aws-internet-gateway-' + self.cluster_name
        internet_gateway.specification.vpc_name = vpc_name
        return internet_gateway

    def get_routing_table(self, vpc_name, internet_gateway_name):
        route_table = self.get_config_or_default(self.docs, 'infrastructure/route-table')
        route_table.specification.name = 'aws-route-table-' + self.cluster_name
        route_table.specification.vpc_name = vpc_name
        route_table.specification.route.gateway_name = internet_gateway_name
        return route_table

    def get_public_key(self):
        public_key_config = self.get_config_or_default(self.docs, 'infrastructure/public-key')
        public_key_config.specification.name = self.cluster_model.specification.admin_user.name

        with open(self.cluster_model.specification.admin_user.key_path+'.pub', 'r') as stream:
            public_key_config.specification.public_key = stream.read().rstrip()

        return public_key_config

    def add_security_rules_inbound_efs(self, infrastructure, security_group):
        ags_allowed_to_efs = select_all(infrastructure, lambda item: item.kind == 'infrastructure/virtual-machine' and
                                                      item.specification.authorized_to_efs)

        for asg in ags_allowed_to_efs:
            subnet = select_single(infrastructure, lambda item: item.kind == 'infrastructure/subnet' and
                                                               item.specification.name == asg.specification.subnet)

            rule_defined = select_first(security_group.specification.rules, lambda item: item.source_address_prefix == subnet.specification.cidr_block
                                                                                        and item.destination_port_range == 2049)
            if rule_defined is None:
                rule = self.get_config_or_default(self.docs, 'infrastructure/security-group-rule')
                rule.specification.name = 'sg-rule-nfs-default-from-'+subnet.specification.name
                rule.specification.direction = 'ingress'
                rule.specification.protocol = 'tcp'
                rule.specification.description = 'NFS inbound for '+subnet.specification.name
                rule.specification.access = 'Allow'

                rule.specification.source_port_range = -1
                rule.specification.destination_port_range = 2049

                rule.specification.source_address_prefix = subnet.specification.cidr_block
                rule.specification.destination_address_prefix = '*'
                security_group.specification.rules.append(rule.specification)

    @staticmethod
    def efs_add_mount_target_config(efs_config, subnet_name):
        target = select_first(efs_config.specification.mount_targets, lambda item: item['subnet_name'] == subnet_name)
        if target is None:
            efs_config.specification.mount_targets.append({'name': 'efs-'+subnet_name+'-mount', 'subnet_name': subnet_name})

    @staticmethod
    def has_efs_any_mounts(efs_config):
        if len(efs_config.specification.mount_targets) > 0:
            return True
        return False

    @staticmethod
    def set_image_id_for_launch_configuration(cluster_model, docs, launch_configuration, autoscaling_group):
        with APIProxy(cluster_model, docs) as proxy:
            image_id = proxy.get_image_id(autoscaling_group.specification.os_full_name)
            launch_configuration.specification.image_id = image_id

    @staticmethod
    def get_config_or_default(docs, kind):
        config = select_first(docs, lambda x: x.kind == kind)
        if config is None:
            return load_yaml_obj(types.DEFAULT, 'aws', kind)
        return config

    @staticmethod
    def get_virtual_machine(component_value, cluster_model, docs):
        machine_selector = component_value.machine
        model_with_defaults = select_first(docs, lambda x: x.kind == 'infrastructure/virtual-machine' and
                                                                 x.name == machine_selector)
        if model_with_defaults is None:
            model_with_defaults = merge_with_defaults(cluster_model.provider, 'infrastructure/virtual-machine',
                                                      machine_selector)

        return model_with_defaults