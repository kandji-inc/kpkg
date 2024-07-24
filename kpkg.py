#!/usr/bin/env python3
# Created 03/05/24; NRJA
# Updated 04/15/24; NRJA
# Updated 05/21/24; NRJA
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

#################
##### ABOUT #####
#################

"""Kandji Packages (kpkg): standalone tool for programmatic management of Kandji Custom Apps"""

#######################
####### IMPORTS #######
#######################

import argparse
import logging
import os
import platform
import shutil
import sys
from pathlib import Path

import requests
from helpers.configs import Configurator
from helpers.utils import Utilities, sha256_file, source_from_brew

#############################
######### ARGUMENTS #########
#############################

# Set parsers at the top so they're available to all funcs below
parser = argparse.ArgumentParser(
    prog="kpkg",
    description="Kandji Packages: standalone tool for programmatic management of Kandji Custom Apps",
)
parser.add_argument(
    "-p",
    "--pkg",
    action="append",
    required=False,
    metavar="PATH",
    help="Path to PKG/DMG for Kandji upload; multiple items can be specified so long as no name/category flags (-n/-t/-s/-z) are passed",
)
parser.add_argument(
    "-b",
    "--brew",
    action="append",
    required=False,
    metavar="CASK",
    help="Homebrew cask name which sources PKG/DMG; multiple items can be specified so long as no name/category flags (-n/-t/-s/-z) are passed",
)
parser.add_argument(
    "-n",
    "--name",
    action="store",
    required=False,
    help="Name of Kandji Custom App to create/update",
)
parser.add_argument(
    "-t",
    "--testname",
    action="store",
    required=False,
    help="Name of Kandji Custom App (test) to create/update",
)
parser.add_argument(
    "-s",
    "--sscategory",
    action="store",
    required=False,
    help="Kandji Self Service category aligned with --name",
)
parser.add_argument(
    "-z",
    "--zzcategory",
    action="store",
    required=False,
    help="Kandji Self Service category aligned with --testname",
)
parser.add_argument(
    "-c",
    "--create",
    action="store_true",
    required=False,
    default=False,
    help="Creates a new Custom App, even if duplicate entry (by name) already exists",
)
parser.add_argument(
    "-d",
    "--debug",
    action="store_true",
    required=False,
    default=False,
    help="Sets logging level to debug with maximum verbosity",
)
parser.add_argument(
    "-v",
    "--version",
    action="store_true",
    required=False,
    default=False,
    help="Returns the current version of Kandji Packages and exits",
)
parser.add_argument(
    "-y",
    "--dry",
    action="store_true",
    required=False,
    default=False,
    help="Sets dry run, returning (not executing) changes to stdout as they would have been made in Kandji",
)
args = parser.parse_args()

###########################
######### LOGGING #########
###########################

# Get hostname for log record
hostname = platform.node()
# Local logging location
path_to_log = os.path.expanduser("~/Library/KandjiPackages/kpkg.log")

logging_level = logging.DEBUG if args.debug else logging.INFO

logging.basicConfig(
    level=logging_level,
    format="{asctime} " + f"[{hostname}]" + ": {levelname}: {message}",
    handlers=[logging.FileHandler(path_to_log), logging.StreamHandler()],
    style="{",
    datefmt="%Y-%m-%d %I:%M:%S %p",
)

log = logging.getLogger(__name__)

# Capture script exec path
script_path = Path(__file__).resolve()
# Get parent dir
parent_dir = script_path.parents[1]
# Uncomment below if running locally
# parent_dir = script_path.parent # noqa: ERA001


def format_stdout(body):
    """Formats provided str with #s to create a header"""
    hashed_body = f"####### {body} #######"
    hashed_header_footer = "#" * len(hashed_body)
    hashed_out = f"\n\n{hashed_header_footer}\n{hashed_body}\n{hashed_header_footer}\n"
    return hashed_out


class KPKG(Configurator, Utilities):
    def __init__(self, path_to_pkg, parent_dir):
        """
        Creates an object for Kandji API interaction
        """
        if not os.path.exists(path_to_pkg):
            log.fatal(f"Provided path '{path_to_pkg}' does not exist!")
            sys.exit(1)
        # Define vars from arg input
        self.arg_pkg_path = path_to_pkg
        self.parent_dir = parent_dir
        self.arg_app_name = args.name
        self.arg_test_name = args.testname
        self.arg_prod_name = self.arg_app_name if self.arg_test_name is not None else None
        self.arg_ss_category = args.sscategory
        self.arg_test_category = args.zzcategory
        self.arg_dry_run = args.dry
        self.arg_create_new = args.create
        self.pkg_path = None
        self.pkg_uploaded = False
        if self.arg_pkg_path is None:
            log.fatal("No PKG path provided (use flag -p/--pkg)")
            sys.exit(1)

    ####################################
    ######### PUBLIC FUNCTIONS #########
    ####################################

    def upload_custom_app(self):
        """Calls func to generate S3 presigned URL (response assigned to self.s3_generated_req)
        Formats presigned URL response to cURL syntax valid for form submission, also appending path to PKG
        Assigns upload form and POST URL to vars for cURL execution
        Runs command and validates output when returning self._validate_response()"""

        def _generate_s3_req():
            """Generates an S3 presigned URL to upload a PKG"""
            post_url = self.api_upload_pkg_url
            form_data = {"name": self.pkg_name}
            response = requests.post(post_url, headers=self.auth_headers, params=self.params, json=form_data)
            return self._validate_response(response, "presign")

        if self.pkg_uploaded is True:
            log.info("PKG already uploaded... Continuing")
            return True

        if not _generate_s3_req():
            return False

        # Assign S3 return data to vars
        upload_url = self.s3_generated_req.get("post_url")
        s3_data = self.s3_generated_req.get("post_data")
        self.s3_key = self.s3_generated_req.get("file_key")
        s3_data["file"] = open(self.pkg_path, "rb")

        if self.dry_run is True:
            log.info(f"DRY RUN: Would upload PKG '{self.pkg_path} as POST to '{upload_url}'")
            return True
        log.info(f"Beginning file upload of '{self.pkg_name}'...")
        response = requests.post(upload_url, files=s3_data)
        return self._validate_response(response, "upload")

    def create_custom_app(self):
        """Assigns creation data and POST URL to vars for cURL execution
        Runs command and validates output when returning self._validate_response()"""
        # Assign initial data with known vars
        create_data = {
            "name": self.custom_app_name,
            "install_type": self.install_type,
            "install_enforcement": self.custom_app_enforcement,
        }
        if self.custom_app_enforcement == "continuously_enforce":
            with open(self.audit_script_path) as f:
                audit_script = f.read()
            create_data["audit_script"] = audit_script
        elif self.custom_app_enforcement == "no_enforcement":
            # If no enforcement, set to show in Self Service
            create_data["show_in_self_service"] = True
            # Setting Self Service also requires a category
            if self.test_app is True:
                # If test app, assign test category ID
                create_data["self_service_category_id"] = self.test_category_id
            else:
                # Otherwise assign as prod app
                create_data["self_service_category_id"] = self.ss_category_id
        if self.upload_custom_app() is not True:
            return False
        create_data["file_key"] = self.s3_key
        # Set POST URL
        post_url = self.api_custom_apps_url
        if self.dry_run is True:
            log.info(
                f"DRY RUN: Would create Custom App '{self.custom_app_name}' with POST to '{post_url}' and fields '{create_data}'"
            )
            return True
        response = requests.post(post_url, headers=self.auth_headers, params=self.params, json=create_data)
        return self._validate_response(response, "create")

    def update_custom_app(self):
        """Assigns update data and PATCH URL to vars for cURL execution
        Runs command and validates output when returning self._validate_response()"""

        def get_custom_apps():
            """Queries all custom apps from Kandji tenant; assigns GET URL to var for cURL execution
            Runs command and validates output when returning self._validate_response()"""
            get_url = self.api_custom_apps_url
            response = requests.get(get_url, headers=self.auth_headers)
            # Assigns self.custom_apps
            return self._validate_response(response, "get")

        # Raise if our custom apps GET fails
        if not get_custom_apps():
            raise Exception

        if self.custom_app_name is not None:
            lib_item_dict = self._find_lib_item_match()

        # Returns None if multiple matches, False if no matches
        if lib_item_dict is None:
            return False
        if lib_item_dict is False:
            if self.default_auto_create is True:
                return self.create_custom_app()
            else:
                log.error("Could not locate existing custom app to update")
                log.error("Auto-create is disabled — skipping remaining steps")
                return False

        # Assign existing LI name, UUID, enforcement, and sha256
        lib_item_name = lib_item_dict.get("name")
        lib_item_uuid = lib_item_dict.get("id")
        lib_item_enforcement = lib_item_dict.get("install_enforcement")
        lib_item_shasum = lib_item_dict.get("sha256")

        # Get sha256 of local media
        local_media_shasum = sha256_file(self.pkg_path)

        log.info(f"Proceeding to update existing custom app '{lib_item_name}'")

        if local_media_shasum == lib_item_shasum:
            log.warning(f"Pending upload '{self.pkg_name}' identical to existing '{lib_item_name}' installer")
            log.info("Skipping upload/update...\n")
            return True

        if self.upload_custom_app() is not True:
            return False

        # Update body with updated package location once uploaded
        update_data = {"file_key": self.s3_key}
        # Validate enforcement of existing LI
        if lib_item_enforcement == "continuously_enforce":
            # If existing LI enforcement differs from set value, override var to Kandji value
            if self.custom_app_enforcement != lib_item_enforcement:
                log.info("Existing app enforcement differs from local config... Deferring to Kandji enforcement type")
                # This info is needed for auditing/enforcement, so split the PKG and find if req values unset
                try:
                    self.app_vers
                    log.debug("Skipping PKG expansion as app version already known")
                except (AttributeError, NameError):
                    log.debug("Proceeding with PKG expansion to populate ID/version...")
                    self._expand_pkg_get_info()
                # Call audit customization here since not invoked earlier
                self._customize_audit_for_upload()
                self.custom_app_enforcement = lib_item_enforcement
            with open(self.audit_script_path) as f:
                audit_script = f.read()
                update_data["audit_script"] = audit_script
        patch_url = os.path.join(self.api_custom_apps_url, lib_item_uuid)
        if self.dry_run is True:
            log.info(
                f"DRY RUN: Would update Custom App '{lib_item_name}' with PATCH to '{patch_url}' and fields '{update_data}'"
            )
            return True
        response = requests.patch(patch_url, headers=self.auth_headers, params=self.params, json=update_data)
        return self._validate_response(response, "update")

    def kandji_customize_create_update(self):
        """Parent function to process any audit script updates and
        either create a net new or update an existing custom app"""
        self._customize_audit_for_upload() if self.custom_app_enforcement == "continuously_enforce" else True
        # If flag override is set, create new app regardless of existing
        if self.arg_create_new is True:
            self.create_custom_app()
        else:
            self.update_custom_app()
        self._restore_audit() if self.custom_app_enforcement == "continuously_enforce" else True

    def main(self):
        """Main function to execute KPKG"""
        try:
            self.get_install_media_metadata()
        except OSError:
            return False
        # Reads config and assigns needed vars for runtime
        # Also validates and populates values for Kandji/Slack (if defined)
        self.populate_from_config()
        self.audit_script_path = os.path.join(parent_dir, self.audit_script)

        if self.custom_app_enforcement == "continuously_enforce":
            # This info is needed for auditing/enforcement, so split the PKG and find it
            self._expand_pkg_get_info()

        ###################
        #### MAIN EXEC ####
        ###################
        # Iterate over dict specifying app type and name
        for key, value in self.app_names.items():
            if key == "test_name":
                self.custom_app_name = value
                self.test_app, self.prod_app = True, False
            elif key == "prod_name":
                self.custom_app_name = value
                self.test_app, self.prod_app = False, True
            else:
                self.test_app, self.prod_app = False, False
            # Main func for processing Cr/Up ops
            self.kandji_customize_create_update()
            # Clean up copied PKG if it exists
        if hasattr(self, "copied_pkg_path") and self.copied_pkg_path is not None:
            try:
                os.remove(self.copied_pkg_path)
            except PermissionError:
                shutil.rmtree(self.copied_pkg_path)
        # Clean up temp dir used for PKG/DMG expansion
        self._expand_pkg_get_info(cleanup=True)


##############
#### BODY ####
##############

if __name__ == "__main__":
    if os.geteuid() == 0:
        log.fatal("kpkg should NOT be run as superuser! Exiting...")
        sys.exit(1)

    packages = []

    with open(os.path.join(script_path.parent, "VERSION")) as f:
        vers = f.read().strip()

    if args.version:
        print(f"Kandji Packages: {vers}")
        sys.exit(0)

    if args.pkg is None and args.brew is None:
        log.fatal("No PKG/DMG path or Homebrew cask provided (use flag -p/--pkg or -b/--brew)")
        sys.exit(1)

    if args.pkg is not None:
        packages.extend(args.pkg)

    if args.brew is not None:
        for brew in args.brew:
            downloaded_brew = source_from_brew(brew)
            packages.append(downloaded_brew) if downloaded_brew is not None else False

    if len(packages) > 1 and any((args.name, args.testname, args.sscategory, args.zzcategory)):
        log.fatal("Multiple brew casks/installers provided, but flags passed for name/category are ambiguous")
        log.info("Use package map or defaults to populate metadata when specifying multiple items")
        sys.exit(1)

    log.info(format_stdout(f"Kandji Packages ({vers})"))

    for pkg in packages:
        log.info(f"\nProcessing '{os.path.basename(pkg)}'")
        kpkg = KPKG(path_to_pkg=pkg.strip(), parent_dir=parent_dir)
        kpkg.main()
    log.info(format_stdout("Kandji Packages Runtime Complete"))
