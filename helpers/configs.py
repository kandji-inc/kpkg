#!/usr/bin/env python3
# Created 01/16/24; NRJA
# Updated 02/20/24; NRJA
################################################################################################
# License Information
################################################################################################
#
# Copyright 2024 Kandji, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
# to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.
#
################################################################################################

#######################
####### IMPORTS #######
#######################

import json
import logging
import os
import plistlib
import re
import sys

import requests

###########################
######### LOGGING #########
###########################

log = logging.getLogger(__name__)


class Configurator:
    """Reads and sets variables based on configured settings"""

    #####################################
    ######### PRIVATE FUNCTIONS #########
    #####################################

    def _parse_enforcement(self, enforcement):
        """Translates provided enforcement val between config values and API-valid values"""
        match enforcement.lower():
            case "audit_enforce":
                parsed_enforcer = "continuously_enforce"
            case "self_service":
                parsed_enforcer = "no_enforcement"
            case "continuously_enforce":
                parsed_enforcer = "audit_enforce"
            case "no_enforcement":
                parsed_enforcer = "self_service"
            case "install_once":
                parsed_enforcer = "install_once"
            case _:
                return False
        return parsed_enforcer

    def _read_config(self, kandji_conf):
        """Read in configuration from defined conf path
        Building out full path to read and load as JSON data
        Return loaded JSON data once existence and validity are confirmed"""
        # Have to derive path this way in order to get the execution file origin
        kandji_conf_path = os.path.join(self.parent_dir, kandji_conf)
        if not os.path.exists(kandji_conf_path):
            log.fatal(f"kpkg config not found at '{kandji_conf_path}'! Validate its existence and try again")
            sys.exit(1)
        try:
            with open(kandji_conf_path) as f:
                custom_config = json.loads(f.read())
        except ValueError as ve:
            log.fatal(
                f"Config at '{kandji_conf_path}' is not valid JSON!\n{ve} — validate file integrity for '{kandji_conf}' and try again"
            )
            sys.exit(1)
        return custom_config

    def _populate_package_map(self):
        """Checks if recipe map is enabled and iters
        to match recipe with custom app name(s)/env(s)"""

        ############################
        # Populate Vars from Mapping
        ############################
        # Initialize vars
        self.package_map = None
        self.app_names = {}
        if self.kpkg_config.get("use_package_map") is True:
            self.package_map = self._read_config(self.package_map_file)
            if self.package_map is False:
                log.error("Package map is enabled, but config is invalid!")
                raise Exception
            self._expand_pkg_get_info(id_query=True)

            for ident, apps in self.package_map.items():
                # Once matching PKG ID found, assign and exit loop
                if ident == self.map_id:
                    log.info(f"Located matching map value '{self.map_id}' from PKG/DMG")
                    self.app_names = apps
                    break
            if not self.app_names:
                log.warning(f"Package map enabled, but no match found for ID '{self.map_id}'!")
                log.info("Will use defaults if no args passed")
        self.map_ss_category = self.app_names.get("ss_category")
        self.map_test_category = self.app_names.get("test_category")

        # Once assigned, remove from dict
        # This ensures we're only iterating over app names
        try:
            self.app_names.pop("ss_category")
        except KeyError:
            pass
        try:
            self.app_names.pop("test_category")
        except KeyError:
            pass

    def _set_defaults_enforcements(self):
        """Reads JSON config and sets enforcement based on
        defined value, otherwise defaults to install once"""
        if (default_vals := self.kpkg_config.get("zz_defaults")) is not None:
            self.default_auto_create = default_vals.get("auto_create_app")
            self.default_custom_name = default_vals.get("new_app_naming")
            self.default_dry_run = default_vals.get("dry_run")
            self.default_dynamic_lookup = default_vals.get("dynamic_lookup")
            self.default_ss_category = default_vals.get("self_service_category")
            self.test_default_ss_category = default_vals.get("test_self_service_category")

        config_enforcement = self.kpkg_config.get("li_enforcement")
        enforcement_type = self._parse_enforcement(config_enforcement.get("type"))
        # Check if enforcement type specified, else default to once
        # May be overridden later based on recipe-specific mappings
        self.custom_app_enforcement = (
            "no_enforcement"
            if (self.map_ss_category or self.arg_ss_category or self.map_test_category or self.arg_test_category)
            is not None
            else enforcement_type
            if enforcement_type
            else "install_once"
        )
        # Assign enforcement delays for audits
        if config_enforcement.get("delays"):
            self.test_delay = config_enforcement.get("delays").get("test")
            self.prod_delay = config_enforcement.get("delays").get("prod")

        self.dry_run = False
        if (self.arg_dry_run or self.default_dry_run) is True:
            log.info("DRY RUN: Will not make any Custom App modifications!\n\n\n")
            self.dry_run = True

    def _set_custom_name(self):
        """Sets and populates self.app_names dict for later iter"""
        # Set assigned name from user passed flag
        self.assigned_name = self.arg_app_name or None
        # Set derived name from queried PKG/DMG metadata
        self.derived_name = self.install_name or self.pkg_path_name
        # If prod and test names defined, assign to dict (overwriting if necessary)
        if self.arg_prod_name is not None:
            self.app_names["prod_name"] = self.arg_prod_name
        if self.arg_test_name is not None:
            self.app_names["test_name"] = self.arg_test_name
        # If "undefined" is set as key name, this func is being called a second time
        # If a PKG is found within a DMG, we are overwriting self.derived_name
        # Run through logic gates again to see if re-assignment is necessary
        if not self.app_names or "undefined" in self.app_names.keys():
            # If not in config, check if custom name(s) passed as args
            if self.assigned_name is not None:
                self.custom_app_name = self.assigned_name
            elif self.default_custom_name is not None:
                self.custom_app_name = self.default_custom_name.replace("APPNAME", self.derived_name)
            # All else fails, assign as 'derived name (kpkg)'
            else:
                self.custom_app_name = f"{self.derived_name} (kpkg)"
            self.app_names["undefined"] = self.custom_app_name

    def _populate_self_service(self):
        def get_self_service():
            """Queries all Self Service categories from Kandji tenant; assigns GET URL to var for cURL execution
            Runs command and validates output when returning self._validate_response()"""
            get_url = f"{self.kandji_api_prefix}/self-service/categories"
            response = requests.get(url=get_url, headers=self.auth_headers)
            return self._validate_response(response, "get_selfservice")

        def name_to_id(ss_name, ss_type):
            """Iterates over self_service list and assigns category ID to var"""
            # Iter over and find matching id for name
            ss_default = (
                self.default_ss_category
                if ss_type == "prod"
                else self.test_default_ss_category
                if ss_type == "test"
                else None
            )
            try:
                ss_assignment = next(
                    category.get("id") for category in self.self_service if category.get("name") == ss_name
                )
            except StopIteration:
                log.warning(
                    f"Provided category '{ss_name}' not found in Self Service!"
                ) if ss_name is not None else None
                try:
                    # Set category id to default (None check performed later)
                    ss_assignment = (
                        next(category.get("id") for category in self.self_service if category.get("name") == ss_default)
                        if ss_default
                        else None
                    )
                except StopIteration:
                    log.warning(f"Default category '{ss_default}' not found in Self Service!")
                    ss_assignment = None
            # Only reassign/override if not already set
            if ss_type == "prod":
                if ss_name is not None:
                    self.ss_category_id = ss_assignment
                else:
                    self.ss_category_id = self.ss_category_id if self.ss_category_id is not None else ss_assignment
            elif ss_type == "test":
                if ss_name is not None:
                    self.test_category_id = ss_assignment
                else:
                    self.test_category_id = (
                        self.test_category_id if self.test_category_id is not None else ss_assignment
                    )

        # Set category IDs to None
        self.ss_category_id, self.test_category_id = None, None

        ############################################
        # Assigns list of dicts to self.self_service
        get_self_service()

        # Create and iter over ad hoc lists with categories/envs
        # If both arg and mapping values defined, override with passed args
        for cat, env in zip(
            [self.map_ss_category, self.map_test_category, self.arg_ss_category, self.arg_test_category],
            ["prod", "test", "prod", "test"],
        ):
            name_to_id(cat, env)

    def _set_slack_config(self):
        """Checks if Slack token name is in config
        Looks up webhook and assigns for use in self.slack_notify()"""

        # Check Slack setting and get/assign webhook
        slack_token_name = (
            self.kandji_slack_opts.get("webhook_name") if self.kandji_slack_opts.get("enabled") is True else None
        )
        self.slack_channel = self._retrieve_token(slack_token_name) if slack_token_name is not None else None

    def _set_kandji_config(self):
        """Validates provided Kandji API URL is valid for use
        Assigns prefix used for API calls + bearer token"""

        # Ensure Kandji API URL is prefixed with https://
        self.kandji_api_url = self._ensure_https(self.kandji_api_url)
        self.headers = {"Content-Type": "application/json"}
        # Confirm provided Kandji URL is valid
        kandji_test_url = self.kandji_api_url.replace("api", "web-api")
        response = requests.get(url=kandji_test_url, headers=self.headers)
        if "tenantNotFound" in response.text:
            log.fatal(f"Provided Kandji URL '{self.kandji_api_url}' appears invalid! Cannot upload...")
            sys.exit(1)

        # Assign tenant URL
        self.tenant_url = self.kandji_api_url.replace(".api.", ".")
        # Assign API domain
        self.kandji_api_prefix = os.path.join(self.kandji_api_url, "api", "v1")
        # Define API endpoints
        self.api_custom_apps_url = os.path.join(self.kandji_api_prefix, "library", "custom-apps")
        self.api_upload_pkg_url = os.path.join(self.api_custom_apps_url, "upload")
        self.api_self_service_url = os.path.join(self.kandji_api_prefix, "self-service", "categories")

        # Grab auth token for Kandji API interactions
        kandji_token = self._retrieve_token(self.kandji_token_name)
        if kandji_token is None:
            log.fatal(
                f"ERROR: Could not retrieve token value from key {self.kandji_token_name}! Run 'kpkg-setup' and try again"
            )
            sys.exit(1)
        # Set headers/params for API calls
        self.auth_headers = {"Authorization": f"Bearer {kandji_token}", "Content-Type": "application/json"}
        self.params = {"source": "kpkg"}

    ####################################
    ######### PUBLIC FUNCTIONS #########
    ####################################

    def get_install_media_metadata(self, lookup_again=False):
        """Populates PKG path and name, and validates file type
        to ensure either DMG or PKG is provided
        If DMG, runs diskutil image info to get volume name
        If PKG, runs installer pkginfo to get PKG name
        Supports optional arg to re-trigger lookup of PKG if found in DMG
        If found, overrides app name to use PKG value vs. DMG"""
        self.pkg_path = self.pkg_path or self.arg_pkg_path
        self.pkg_name = os.path.basename(self.pkg_path)
        # Subproc call to determine media type and validity
        if self._run_command(f"hdiutil imageinfo -format '{self.pkg_path}'", nostderr=True) is not False:
            self.install_type = "image"
        elif self._run_command(f"installer -pkginfo -pkg '{self.pkg_path}'", nostderr=True) is not False:
            self.install_type = "package"
        else:
            unsupported_type = self._run_command(f"file --mime-type -b {self.pkg_path}")
            log.error(f"File '{self.pkg_name}' is unsupported type '{unsupported_type}'")
            log.error(f"Confirm '{self.pkg_path}' is valid package/disk image")
            log.error(f"Skipping '{self.pkg_name}'...")
            raise OSError
        if self.install_type == "image":
            shell_cmd = f"diskutil image info -plist '{self.pkg_path}'"
            diskutil_out = self._run_command(shell_cmd, nostderr=True)
            if diskutil_out is False:
                log.warning("Could not retrieve diskutil info for provided DMG")
                log.warning("Pending EULA may be blocking mount or invalid DMG")
                self.install_name = None
            else:
                diskutil_plist_out = plistlib.loads(diskutil_out.encode())
                self.install_name = next(
                    disk.get("volume-name")
                    for disk in diskutil_plist_out.get("Partitions")
                    if "N/A" not in disk.get("volume-name")
                )
        elif self.install_type == "package":
            # Subproc call to get PKG name
            shell_cmd = f"installer -pkginfo -pkg '{self.pkg_path}'"
            pkginfo_out = self._run_command(shell_cmd)
            try:
                pkginfo_out = pkginfo_out.splitlines()[0]
            except (IndexError, AttributeError):
                pass
            self.install_name = pkginfo_out if pkginfo_out is not False else None
        # non-capture group matches on optional 64 char hex string
        # capture matches one or more word and/or whitespace chars (non-greedy)
        # non-capture positive lookahead assertion to indicate match will be found before version or dashes
        name_only_pattern = re.compile(r"(?:[a-f0-9]{64}--)?([\w\s]+?)(?=\s+\d+\.\d+|[.-])")
        if self.install_name:
            log.debug(f"regex searching {name_only_pattern} against {self.install_name}\nOutput is below:")
            # If PKG/DMG name found, strip out version and other metadata
            log.debug(re.search(name_only_pattern, self.install_name))
            try:
                self.install_name = re.search(name_only_pattern, self.install_name).group(1)
            except AttributeError as err:
                log.debug(f"Installer name {self.install_name} couldn't be filtered further; leaving unchanged\n{err}")
        # If no name returned from above, run PKG basename thru re filter to approximate a usable name
        self.pkg_path_name = (
            None if self.install_name else re.search(name_only_pattern, os.path.basename(self.pkg_path)).group(1)
        )
        if lookup_again is True:
            self._populate_package_map()
            self._set_defaults_enforcements()
            self._set_custom_name()

    def populate_from_config(self):
        """Read in configuration from defined conf path
        Building out full path to read and load as JSON data
        Return loaded JSON data once existence and validity are confirmed"""

        self.config_file = "config.json"
        self.package_map_file = "package_map.json"
        self.audit_script = "audit_app_and_version.zsh"
        # If env-specific custom app name(s) are defined, these'll be overwritten below
        self.test_app, self.prod_app = False, False
        # Temp dir/path for PKG/DMG expansion to be overwritten later
        self.temp_dir, self.tmp_pkg_path, self.tmp_dmg_mount = None, None, None
        # Populate config
        self.kpkg_config = self._read_config(self.config_file)
        if self.kpkg_config is False:
            raise Exception("ERROR: Config is invalid! Confirm file integrity and try again")
        try:
            kandji_conf = self.kpkg_config["kandji"]
            self.kandji_api_url = kandji_conf["api_url"]
            self.kandji_token_name = kandji_conf["token_name"]
            self.token_keystores = self.kpkg_config["token_keystore"]
            # Overwrite Kandji API URL from ENV or keep as set in config
            self.kandji_api_url = os.environ.get("KANDJI_API_URL", self.kandji_api_url)
            # Overwrite keystore conf from ENV if set
            if "ENV_KEYSTORE" in os.environ:
                self.token_keystores["environment"] = True
            # Sanity check values before continuing
            if "TENANT" in self.kandji_api_url:
                log.fatal("Kandji API URL is invalid! Run '/usr/local/bin/kpkg-setup' and try again")
                sys.exit(1)
            if not any(self.token_keystores.values()):
                log.fatal("Token keystore is undefined! Run '/usr/local/bin/kpkg-setup' and try again")
                sys.exit(1)
            self.kandji_slack_opts = self.kpkg_config["slack"]
        except KeyError as err:
            log.fatal(f"Required key(s) are undefined! {' '.join(err.args)}")
            sys.exit(1)

        self._populate_package_map()
        self._set_defaults_enforcements()
        self._set_custom_name()
        self._set_slack_config()
        self._set_kandji_config()
        self._populate_self_service()
