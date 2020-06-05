import os
import copy

from cli.helpers.Step import Step
from cli.helpers.build_saver import get_ansible_path, get_ansible_path_for_build, get_ansible_vault_path
from cli.helpers.doc_list_helpers import select_first
from cli.helpers.naming_helpers import to_feature_name, to_role_name
from cli.helpers.ObjDict import ObjDict
from cli.helpers.yaml_helpers import dump
from cli.helpers.Config import Config
from cli.helpers.data_loader import load_yaml_obj, types, load_all_documents_from_folder


class AnsibleVarsGenerator(Step):

    def __init__(self, inventory_creator=None, inventory_upgrade=None):
        super().__init__(__name__)

        self.inventory_creator = inventory_creator
        self.inventory_upgrade = inventory_upgrade
        self.roles_with_generated_vars = []

        if inventory_creator != None and inventory_upgrade == None:
            self.cluster_model = inventory_creator.cluster_model
            self.config_docs = [self.cluster_model] + inventory_creator.config_docs
        elif inventory_upgrade != None and inventory_creator == None:
            self.cluster_model = inventory_upgrade.cluster_model
            self.config_docs = load_all_documents_from_folder('common', 'defaults/configuration')
        else:
            raise Exception('Invalid AnsibleVarsGenerator configuration')

    def __enter__(self):
        super().__enter__()
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        super().__exit__(exc_type, exc_value, traceback)

    def generate(self):
        self.logger.info('Generate Ansible vars')
        self.is_upgrade_run = self.inventory_creator == None
        if self.is_upgrade_run:
            ansible_dir = get_ansible_path_for_build(self.inventory_upgrade.build_dir)
        else:
            ansible_dir = get_ansible_path(self.cluster_model.specification.name)

        cluster_config_file_path = os.path.join(ansible_dir, 'roles', 'common', 'vars', 'main.yml')
        clean_cluster_model = self.get_clean_cluster_model()
        with open(cluster_config_file_path, 'w') as stream:
            dump(clean_cluster_model, stream)

        if self.is_upgrade_run:
            # For upgrade at this point we don't need any of other roles then
            # common, upgrade, repository and image_registry.
            # - commmon is already provisioned from the cluster model constructed from the inventory.
            # - upgrade should not require any additional config
            # roles in the list below are provisioned for upgrade from defaults
            enabled_roles = ['repository', 'image_registry']
        else:
            enabled_roles = self.inventory_creator.get_enabled_roles()

        for role in enabled_roles:
            document = select_first(self.config_docs, lambda x: x.kind == 'configuration/'+to_feature_name(role))

            if document is None:
                self.logger.warn('No config document for enabled role: ' + role)
                continue

            document.specification['provider'] = self.cluster_model.provider
            self.write_role_vars(ansible_dir, role, document)

        self.populate_group_vars(ansible_dir)

    def write_role_vars(self, ansible_dir, role, document):
        vars_dir = os.path.join(ansible_dir, 'roles', to_role_name(role), 'vars')
        if not os.path.exists(vars_dir):
            os.makedirs(vars_dir)

        vars_file_name = 'main.yml'
        vars_file_path = os.path.join(vars_dir, vars_file_name)

        with open(vars_file_path, 'w') as stream:
            dump(document, stream)

        self.roles_with_generated_vars.append(to_role_name(role))

    def populate_group_vars(self, ansible_dir):
        main_vars = ObjDict()
        main_vars['admin_user'] = self.cluster_model.specification.admin_user
        main_vars['validate_certs'] = Config().validate_certs
        main_vars['offline_requirements'] = Config().offline_requirements
        main_vars['wait_for_pods'] = Config().wait_for_pods
        main_vars['is_upgrade_run'] = self.is_upgrade_run
        main_vars['roles_with_generated_vars'] = sorted(self.roles_with_generated_vars)

        shared_config_doc = select_first(self.config_docs, lambda x: x.kind == 'configuration/shared-config')
        if shared_config_doc == None:
            shared_config_doc = load_yaml_obj(types.DEFAULT, 'common', 'configuration/shared-config')
        
        self.set_vault_path(shared_config_doc)
        main_vars.update(shared_config_doc.specification)

        vars_dir = os.path.join(ansible_dir, 'group_vars')
        if not os.path.exists(vars_dir):
            os.makedirs(vars_dir)

        vars_file_name = 'all.yml'
        vars_file_path = os.path.join(vars_dir, vars_file_name)

        with open(vars_file_path, 'a') as stream:
            dump(main_vars, stream)

    def set_vault_path(self, shared_config):
        if shared_config.specification.vault_location == '':
            shared_config.specification.vault_tmp_file_location = Config().vault_password_location
            cluster_name = self.get_cluster_name()
            shared_config.specification.vault_location = get_ansible_vault_path(cluster_name)
    
    def get_cluster_name(self):
        if 'name' in self.cluster_model.specification.keys():
            return self.cluster_model.specification.name
        elif self.inventory_upgrade is not None:
            return os.path.basename(self.inventory_upgrade.build_dir)
        return 'default'

    def get_clean_cluster_model(self):
        cluster_model = copy.copy(self.cluster_model)
        self.clear_object(cluster_model, 'credentials')
        return cluster_model

    def clear_object(self, obj_to_clean, key_to_clean):
        for key, val in obj_to_clean.items():
            if key == key_to_clean:
                obj_to_clean[key] = ''
                continue
            if isinstance(obj_to_clean[key], ObjDict):
                self.clear_object(obj_to_clean[key], key_to_clean)
