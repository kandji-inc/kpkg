#!/bin/zsh
# Created 02/05/24; NRJA
# Updated 07/18/24; NRJA
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

#############################
######### ARGUMENTS #########
#############################

# Provide arg support to only set config file
zparseopts -D -E -a opts h -help a -addcask b -brewcron c -config i -idfind m -map r -reset u -uninstall
# Set args for help and show message
if (( ${opts[(I)(-h|--help)]} )); then
    /bin/cat <<EOF
Usage: kpkg-setup [-h/--help|-a/--addcask|-b/--brewcron|-c/--config|-i/--idfind|-m/--map|-r/--reset|-u/--uninstall]

Conducts prechecks to ensure all required dependencies are available prior to runtime.
Once confirmed, reads and prompts to populate values in config.json if any are invalid.

Options:
-h, --help                       Show this help message and exit
-a, --addcask                    Prompt to add new cask values to brew_cron.json; write updated values to LaunchAgent and reload (must be paired with -b/--brewcron)
-b, --brewcron                   Prompt to populate brew_cron.json (if missing) or read in existing config; write provided values to LaunchAgent and load
-c, --config                     Configure config.json with required values for runtime (don't store secrets)
-i, --idfind                     Populate to CSV names and ids of provided installer media (accepts .pkg/dmg or dir of .pkgs/dmgs)
-m, --map                        Populate to CSV usable values for package_map.json
-r, --reset                      Prompt to reset/overwrite configurable variables/secrets
-u, --uninstall                  Unload and remove agent from ~/Library/LaunchAgents/io.kandji.kpkg.brewcron.plist (must be paired with -b/--brewcron)
EOF
    exit 0
fi

##############################
########## VARIABLES #########
##############################

# Get username and UID
user=$(/usr/bin/stat -f%Su /dev/console)
uid=$(/usr/bin/stat -f%Du /dev/console)

# Get local dir name
dir=$(dirname $(realpath ${ZSH_ARGZERO}))
# Assign full path
abs_dir=$(realpath ${dir})
# Hardcoded filename for configs
config_name="config.json"
# Hardcoded filename for configs
config_file="${abs_dir}/${config_name}"

# Find version file and assign
version_path=$(find "${abs_dir}" -name VERSION)
version=$(cat "${version_path}")

# Set service name and pathing for LaunchAgent
sv_name="io.kandji.kpkg.brewcron"
user_agents="/Users/${user}/Library/LaunchAgents"
kpkg_brewcron="${user_agents}/${sv_name}.plist"
# Hardcoded filename for configs
bc_config_name="brew_cron.json"
bc_config_file="${abs_dir}/${bc_config_name}"

# RE matching for Kandji API URL
kandji_api_re='^[A-Za-z0-9]+\.api(\.eu)?\.kandji\.io$'
# xdigit is an RE pattern match for valid hex chars
kandji_token_re='[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}'
slack_webhook_re='https://hooks.slack.com/services/[[:alnum:]]{9,11}/[[:alnum:]]{11}/[[:alnum:]]{24}'
# Matching to confirm hours input is valid
bc_frequency_hours_re='[[:digit:]]{1,4}'
# alphanumeric strings may contain hyphens, separated by commas
bc_casks_input_re='^([[:alnum:]]+(-[[:alnum:]]+)*)(\s*,\s*[[:alnum:]]+(-[[:alnum:]]+)*)*$'

# Get login keychain for user
user_keychain_path=$(security login-keychain | xargs)

# Assoc. arr to store PKG/DMG names and IDs
declare -A install_media_ids

# Arr to hold cask names
declare -a casks

##############################
########## FUNCTIONS #########
##############################

##############################################
# Formats provided text with ###s to create
# section bodies + headers/footers
##############################################
function format_stdout() {
    body=${1}
    # Formats provided str with #s to create a header
    hashed_body="####### ${body} #######"
    # shellcheck disable=SC2051
    hashed_header_footer=$(printf '#%.0s' {1..$#hashed_body})
    echo "\n\n${hashed_header_footer}\n${hashed_body}\n${hashed_header_footer}\n"
}

##############################################
# Determines media type based on provided
# path; calls hdiutil to verify if valid DMG
# Calls installer to verify if valid PKG
# If neither, calls file to get mime type
# Arguments:
#  media_path; ${1}
# Returns:
#  Prints media type to stdout for assignment
##############################################
function determine_media_type() {
    media_path="${1}"

    # See man zshmisc under ALTERNATE FORMS FOR COMPLEX COMMANDS
    # shellcheck disable=SC1050,SC1141
    if (hdiutil imageinfo -format "${media_path}" >/dev/null 2>&1) media_type="dmg"
    if (installer -pkginfo -pkg "${media_path}" >/dev/null 2>&1) media_type="pkg"
    if [[ -z ${media_type} ]]; then
        media_type=$(file --mime-type -b ${media_path})
    fi
    printf "${media_type}"
}

##############################################
# Reads in config.json and assigns values
# to global vars; if any are undefined,
# prompts user to populate interactively
# Calls prechecks to validate config
# Globals:
#  config_file
# Assigns:
#  kandji_api
#  kandji_token_name
#  env_store
#  keychain_store
#  slack_enabled
#  slack_token_name
##############################################
function read_config() {
    # Read in configs and assign to vars
    kandji_api=$(plutil -extract kandji.api_url raw -o - "${config_file}")
    kandji_token_name=$(plutil -extract kandji.token_name raw -o - "${config_file}")
    # Ensure at least one enabled keystore val
    env_store=$(plutil -extract token_keystore.environment raw -o - "${config_file}")
    keychain_store=$(plutil -extract token_keystore.keychain raw -o - "${config_file}")
    # Check if Slack enabled and read in webhook name
    slack_enabled=$(plutil -extract slack.enabled raw -o - "${config_file}")
    slack_token_name=$(plutil -extract slack.webhook_name raw -o - "${config_file}")
    use_package_map=$(plutil -extract use_package_map raw -o - "${config_file}")
}


##############################################
# Prompts interactively to reset existing
# values in config.json as well as stored
# secrets; once value is reset, marked True so
# as to not prompt indefinitely
##############################################
function reset_values() {
    echo "\n$(date +'%r') : Running setup to reset existing values"
    if ! ${reset_kandji_url}; then
        reset_kandji_url=true
        set_kandji_api_url
    fi
    if ! ${reset_keystore}; then
        reset_keystore=true
        set_keystore
    fi
    # Re-read config to update vars
    read_config
    if [[ -n ${kandji_token_name} ]]; then
        if ! ${reset_kandji_token}; then
            token_type="Kandji"
            prompt_store_secret
        fi
    else
        echo "$(date +'%r') : Kandji token name not defined in config!"
        exit 1
    fi

    if [[ ${slack_enabled} == true ]]; then
        if ! ${reset_slack_token}; then
            token_type="Slack"
            prompt_store_secret
        fi
    fi
}


##############################################
# Conducts prechecks to ensure all required
# dependencies are available prior to runtime
# and that existing configs are valid
# If any are found to be invalid, prompts
# user to populate interactively
# Globals:
#  kandji_api
#  kandji_token_name
#  env_store
#  keychain_store
#  slack_enabled
#  slack_token_name
#  config_file
# Assigns:
#  token_type
##############################################
function prechecks() {

    if [[ -z ${kandji_api} || $(grep "TENANT\.api" <<< ${kandji_api}) ]]; then
        echo "\n$(date +'%r') : WARNING: No valid Kandji API URL defined in ${config_name}"
        set_kandji_api_url
        # Re-read config to update var
        read_config
        # Re-run prechecks to validate change
        prechecks
        # Return to avoid duplicate prompts
        return
    fi

    if [[ ${env_store} != true && ${keychain_store} != true ]]; then
        echo "\n$(date +'%r') : WARNING: No token keystore defined in ${config_name}"
        set_keystore
        # Re-read config to update var
        read_config
        # Re-run prechecks to validate change
        prechecks
        # Return to avoid duplicate prompts
        return
    fi

    if [[ -n ${kandji_token_name} ]]; then
        token_type="Kandji"
        prompt_store_secret
    else
        echo "$(date +'%r') : CRITICAL: Kandji token name not defined in ${config_name}"
        exit 1
    fi

    if [[ ${slack_enabled} == true && -n ${slack_token_name} ]]; then
        token_type="Slack"
        prompt_store_secret
    fi
}

##############################################
# Validates specified token type and assigns
# token_name to align with indicated type
# Globals:
#   token_type
# Assigns:
#   token_name
# Returns:
#   1 if assigned val token_type is invalid
##############################################
function assign_token_name() {
    case ${token_type} in
        "Kandji")
            token_name=${kandji_token_name}
            secret_regex_pattern=${kandji_token_re}
            reset_token="reset_kandji_token"
            ;;
        "Slack")
            token_name=${slack_token_name}
            secret_regex_pattern=${slack_webhook_re}
            reset_token="reset_slack_token"
            ;;
        *)
            echo "$(date +'%r') : CRITICAL: Token type must be one of Kandji or Slack"
            return 1
            ;;
    esac
}

##############################################
# Prompts interactively to set Kandji API URL
# Once API URL is validated, writes to config
# Globals:
#  kandji_api_re
#  config_file
#  CONFIG_VALUE
# Outputs:
#  Writes input string to config.json
##############################################
function set_kandji_api_url() {
    value_regex_pattern=${kandji_api_re}
    prompt_for_value "Kandji API URL" "INSTANCE.api(.eu).kandji.io"
    plutil -replace kandji.api_url -string ${CONFIG_VALUE} -r "${config_file}"
}

##############################################
# Prompts interactively to set keystore
# for token storage; func recursively calls
# self until at least one keystore is defined
# Outputs:
#  Writes input bool to config.json
##############################################
function set_keystore() {
    echo
    if read -q "?Use ENV for token storage? (Y/N):"; then
        plutil -replace token_keystore.environment -bool true -r "${config_file}"
    else
        plutil -replace token_keystore.environment -bool false -r "${config_file}"
    fi
    echo
    if read -q "?Use keychain for token storage? (Y/N):"; then
        plutil -replace token_keystore.keychain -bool true -r "${config_file}"
    else
        plutil -replace token_keystore.keychain -bool false -r "${config_file}"
    fi
}

##############################################
# Prompts interactively to assign value
# to entry; func recursively calls self until
# value is defined or user interrupts w/SIGINT
# Arguments:
#  key_name; ${1}
#  example_val; ${2}
# Assigns:
#   CONFIG_VALUE
# Returns:
#   Recursively calls func if no val provided
##############################################
function prompt_for_value() {
    key_name=${1}
    example_val=${2}
    echo
    # Disable beautysh read formatting (indents)
    # @formatter:off
    read "CONFIG_VALUE?
Enter value for ${key_name} (e.g. ${example_val}):
"
    # @formatter:on
    if [[ -n ${CONFIG_VALUE} ]]; then
        if grep -q -w -E "${value_regex_pattern}" <<< "${CONFIG_VALUE}"; then
            return 0
        else
            echo "\n$(date +'%r') : Provided value did not match expected sequence!"
            echo "$(date +'%r') : Accepted format is ${example_val}"
            echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
            prompt_for_value ${key_name} ${example_val}
        fi
    else
        echo "\n$(date +'%r') : No value provided!"
        echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
        prompt_for_value ${key_name} ${example_val}
    fi
}

##############################################
# Prompts interactively to assign secret value
# to entry; func recursively calls self until
# token is defined or user interrupts w/SIGINT
# Globals:
#   token_type
# Assigns:
#   BEARER_TOKEN
# Returns:
#   Recursively calls func if no val provided
##############################################
function prompt_for_secret() {
    echo
    # Disable beautysh read formatting (indents)
    # @formatter:off
    read -s "BEARER_TOKEN?Enter ${token_type} token value:
"
    # @formatter:on
    if [[ -n ${BEARER_TOKEN} ]]; then
        if grep -q -w -E "${secret_regex_pattern}" <<< "${BEARER_TOKEN}"; then
            return 0
        else
            echo "\n$(date +'%r') : Provided token did not match expected sequence!"
            echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
            prompt_for_secret
        fi
    else
        echo "\n$(date +'%r') : No value provided for token!"
        echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
        prompt_for_secret
    fi
}

##############################################
# Retrieves token from ENV or keychain
# based on config settings; assigns token to
# global for API calls elsewhere
# Arguments:
#  token_name; ${1}
# Assigns:
#  BEARER_TOKEN
##############################################
function retrieve_token() {
    token_name=${1}
    unset BEARER_TOKEN
    if [[ ${env_store} == true ]]; then
        BEARER_TOKEN=${(P)token_name}
    fi
    if [[ -z ${BEARER_TOKEN} && ${keychain_store} == true ]]; then
        BEARER_TOKEN=$(security find-generic-password -w -a "kpkg" -s ${token_name})
    fi
}

##############################################
# Checks config; if ENV is set to true,
# searches for token by name. If not found,
# prompts user to store secret in ENV
# Func calls itself to validate successful
# lookup of secret from ENV once stored
# Globals:
#   config_file
#   token_name
#   token_type
# Outputs:
#   Writes secret to ENV if not found
##############################################
function check_store_env() {
    # Validate expected secrets are stored if using ENV
    if [[ ${env_store} == true ]]; then
        # Check if env is undefined
        if [[ ! -v ${token_name} ]] || (( ${opts[(I)(-r|--reset)]} )); then
            echo
            if (( ${opts[(I)(-r|--reset)]} )) && check_set_reset_var; then
                return 0
            fi
            if read -q "?Store ${token_type} token in ENV? (Y/N):"; then
                prompt_for_secret "${token_type}"
                user_shell=$(dscl . -read /Users/${user} UserShell | cut -d ":" -f2)
                if grep -q -i zsh <<< ${user_shell}; then
                    dotfile_name=".zshenv"
                elif grep -q -i bash <<< ${user_shell}; then
                    dotfile_name=".bash_profile"
                else
                    dotfile_name=".profile"
                fi
                dotfile_path="/Users/${user}/${dotfile_name}"
                # Export token, write to dotfile
                if grep -q "export ${token_name}=" "${dotfile_path}" >/dev/null 2>&1; then
                    # Update existing token value if present
                    sed -i '' "s|export ${token_name}=.*|export ${token_name}=${BEARER_TOKEN}|g" "${dotfile_path}"
                else
                    echo "export ${token_name}=${BEARER_TOKEN}" >> "${dotfile_path}"
                fi
                # shellcheck disable=SC1090
                source "${dotfile_path}"
                check_store_env
            fi
        else
            echo "\n$(date +'%r') : Valid ${token_type} token set in ENV"
        fi
    fi
}

##############################################
# Checks if reset flag is set; if true, checks
# if specified token is True; if so returns 0
# If not, sets token to true and returns 1
# Globals:
#  reset_token
# Assigns:
#  reset_token
##############################################
function check_set_reset_var() {
    if ${(P)reset_token}; then
        return 0
    fi
    # Have to eval here because reset_token could be Kandji or Slack
    eval ${reset_token}=true
    return 1
}

##############################################
# Checks config; if keychain is set to true,
# searches for token by name. If not found,
# prompts user to store secret in keychain
# (may prompt for PW to first unlock user KC)
# Func calls itself to validate successful
# lookup of secret from keychain once stored
# Globals:
#   token_type
# Outputs:
#   Writes secret to keychain if not found
##############################################
function check_store_keychain() {

    # Validate expected secrets are stored if using keychain
    if [[ ${keychain_store} == true ]]; then
        # Check if keychain value for name is undefined; also proceed is reset flag is set
        if ! security find-generic-password -a "kpkg" -s ${token_name} >/dev/null 2>&1 || (( ${opts[(I)(-r|--reset)]} )); then
            echo
            if (( ${opts[(I)(-r|--reset)]} )) && check_set_reset_var; then
                return 0
            fi
            if read -q "?Store ${token_type} token in user keychain? (Y/N):"; then
                prompt_for_secret "${token_type}"
                echo "\n$(date +'%r') : Adding token to login keychain"
                echo "$(date +'%r') : Enter your password if prompted to unlock keychain"
                if ! security unlock-keychain -u ${user_keychain_path}; then
                    echo "$(date +'%r') : ERROR: Unable to unlock keychain; exiting"
                    exit 1
                fi
                security add-generic-password -U -a "kpkg" -s "${token_name}" -w "${BEARER_TOKEN}" \
                    -T "/usr/bin/security" -T "/Users/${user}/Library/KandjiPackages/kpkg" \
                    -T "/Users/${user}/Library/KandjiPackages/setup.zsh" ${user_keychain_path}
                check_store_keychain
            fi
        else
            echo "\n$(date +'%r') : Valid ${token_type} token set in keychain"
        fi
    fi
}

##############################################
# Assigns token name from provided type
# Checks if ENV and/or keychain set for token
# storage; if true and token not set, prompts
# interactively to place token in store
# Globals:
#   token_type
##############################################
function prompt_store_secret() {
    if [[ ${config_only} == true ]]; then
        echo "\n$(date +'%r') : Running config-only; skipping secrets storage on host"
        return 0
    fi
    assign_token_name
    # Reset for each keystore method
    eval ${reset_token}=false
    check_store_env
    eval ${reset_token}=false
    check_store_keychain
}

function prompt_validate_pkg_pkgs() {

    # Prompt for PKG path
    # Disable beautysh read formatting (indents)
    # @formatter:off
    read "provided_path?Drag 'n' drop a .pkg/dmg (or directory of .pkg/dmgs) for ID lookup:
"
    # @formatter:on
    ftype=$(determine_media_type "${provided_path}")
    # Check if provided path is a directory
    if [[ -d "${provided_path}" ]]; then
        # shellcheck disable=SC2045
        # Split arr entries by newline with (f)
        # Run find command on dir to get PKG files and iterate through
        for media in "${(f)$(find "${provided_path}" -type f)}" ; do
            get_install_media_id "${media}"
        done
        # Validate file type to ensure one of PKG/DMG provided
    elif ! grep -q 'dmg\|pkg' <<< "${ftype}"; then
        echo "File ${provided_path} is not valid! Expected valid .pkg or .dmg; got ${ftype}"
        prompt_validate_pkg_pkgs
        return
    else
        get_install_media_id "${provided_path}"
    fi
    # Once arr is populated, write to .CSV
    write_install_media_ids_to_csv
}

##############################################
# Accepts path to installer media (dmg/pkg)
# Validates installer type and proceeds to
# expand/attach media and locate identifier
# If .app, assigns CFBundleIdentifier to ID
# If .pkg (standalone or in .dmg), assigns
# pkg-info from PackageInfo file to ID
# Results appended to install_media_ids dict
# Globals:
#  install_media_ids
# Arguments:
#   Accepts path to .dmg/.pkg; "${1}"
# Outputs:
#  Expands/attaches media in temp dir
#  Detaches/destroys temp dir
# Assigns:
#  install_media_ids
##############################################
function get_install_media_id() {

    provided_path="${1}"

    # Reset vars for each iteration
    unset primary_id install_type

    # Get media type of provided path
    install_type=$(determine_media_type "${provided_path}")
    # If neither dmg or pkg, invalid installer media or unsupported type
    if ! grep -q 'dmg\|pkg' <<< "${install_type}"; then
        echo "$(date +'%r') : Skipping file '${provided_path}' (corrupt DMG/PKG or unsupported media type '${install_type}')"
        return 1
    fi

    media_path=$(realpath ${provided_path})
    media_name=$(basename ${provided_path})
    # Create sandbox
    tmp_dir=$(mktemp -d)

    if [[ ${install_type} == "dmg" ]]; then
        tmp_mount="${tmp_dir}/dmg_mount"
        if ! hdiutil attach "${media_path}" -mountpoint "${tmp_mount}" -nobrowse -noverify -noautoopen -quiet; then
            # Get /dev/disk mnt point to detach
            mount_point=$(hdiutil info | grep "${media_path}" -A20 | grep -m 1 '/dev/disk' | awk '{print $1}')
            # Detach and try again
            hdiutil detach "${mount_point}" -force -quiet
            sleep 2
            # Try again
            hdiutil attach "${media_path}" -mountpoint "${tmp_mount}" -nobrowse -noverify -noautoopen -quiet
        fi
        # If Applications symlink present, likely a drag 'n' drop .app, even if PKG also found
        apps_symlink=$(find "${tmp_mount}" -maxdepth 1 -type l -name "Applications")
        # Locate any Info.plist files in the mounted DMG
        # If multiple, sort by parent dir size and assign Info.plist with largest parent
        dmg_info_plist=$(find "${tmp_mount}" -type f -path "*Contents/Info.plist" -exec dirname "{}" \; | uniq | xargs -I {} du -sk "{}" | sort -rnk1 | head -1 | awk '{print substr($0,index($0,$2))"/Info.plist"}')
        # Locate any .pkg installers in the mounted DMG
        # If multiple, sort by size and assign largest .pkg installer
        dmg_sub_pkg=$(find "${tmp_mount}" -type f \( -name "*.mpkg" -o -name "*.pkg" \) | uniq | xargs -I {} du -sk "{}" | sort -rnk1 | head -1 | awk '{print substr($0,index($0,$2))}')
        if [[ -n ${apps_symlink} ]]; then
            if [[ -n ${dmg_info_plist} ]]; then
                primary_id=$(plutil -extract CFBundleIdentifier raw -o - "${dmg_info_plist}")
            else
                echo "$(date +'%r') : WARNING: No Info.plist found in ${tmp_mount}"
            fi
        elif [[ -n ${dmg_sub_pkg} ]]; then
            pkg_path="${dmg_sub_pkg}"
        elif [[ -n ${dmg_info_plist} ]]; then
            primary_id=$(plutil -extract CFBundleIdentifier raw -o - "${dmg_info_plist}")
        else
            echo "$(date +'%r') : ERROR: Neither Info.plist nor PKG found in mounted DMG"
        fi
    elif [[ ${install_type} == "pkg" ]]; then
        pkg_path=${media_path}
    fi
    if [[ -z ${primary_id} ]]; then
        # Unpack the package, keeping Payload, PackageInfo, and Distribution (if present)
        xar -x -C "${tmp_dir}" -f "${pkg_path}" --exclude Scripts --exclude Bom --exclude Resources

        # Find and sort PackageInfo(s) by size (largest parent dir first)
        pkg_infos=("${(f)$(find "${tmp_dir}" -type f -name 'PackageInfo' -exec dirname "{}" \; | uniq | xargs -I {} du -sk "{}" | sort -rnk1 | awk '{print substr($0,index($0,$2))"/PackageInfo"}')}") 2>/dev/null
        # Also locate Distro file
        pkg_distro=$(find "${tmp_dir}" -name "Distribution")
        # If more than one, query Distro file for version and match to PackageInfo
        if [[ ${#pkg_infos[@]} -gt 1 ]]; then
            distro_vers=$(xmllint --xpath "string(/*[self::installer-gui-script|self::installer-script]/product/@version)" ${pkg_distro})
            if [[ -n ${distro_vers} ]]; then
                for info in ${pkg_infos[@]}; do
                    matching_id=$(xmllint --xpath 'string(//pkg-info[@version="'${distro_vers}'"]/@identifier)' ${info})
                    if [[ -n ${matching_id} ]]; then
                        primary_id=${matching_id}
                        break
                    fi
                done
            else
                # If no Distro vers, assign from PackageInfo with largest parent dir
                primary_id=$(xmllint --xpath "string(/pkg-info/@identifier)" "${pkg_infos[1]}")
            fi
        elif [[ ${#pkg_infos[@]} -eq 1 ]]; then
            # If just one PackageInfo, assign from that
            primary_id=$(xmllint --xpath "string(/pkg-info/@identifier)" "${pkg_infos[1]}")
        else
            echo "$(date +'%r') : ERROR: No PackageInfo files found in ${tmp_dir}"
            return 1
        fi
    fi
    echo "$(date +'%r') : Located primary ID '${primary_id}' for '${media_name}'"
    # Append primary ID to dict
    install_media_ids[${media_name}]="${primary_id}"
    # Clean up
    hdiutil detach "${tmp_mount}" -force -quiet
    rm -f -R "${tmp_dir}"
}

##############################################
# Writes install media names and IDs to CSV
# If package map is inactive, prompts user to
# enable; opens written CSV in default viewer
# Globals:
#  abs_dir
#  config_file
#  install_media_ids
#  use_package_map
# Outputs:
#  Writes to install_media_ids.csv
#  Toggles on package map if user opts to
##############################################
function write_install_media_ids_to_csv() {
    echo "Filename,ID" > "${abs_dir}/install_media_ids.csv"
    #shellcheck disable=SC1073,SC1072,SC1058
    for pkg pkgid in ${(kv)install_media_ids}; do
        echo "${pkg},${pkgid}" >> "${abs_dir}/install_media_ids.csv"
    done

    if [[ ${use_package_map} != true ]]; then
        echo "$(date +'%r') : Package map currently inactive"
        if read -q "?Enable it now? (from package_map.json) (Y/N):"; then
            plutil -replace use_package_map -bool true -r "${config_file}"
            use_package_map=true
            echo "$(date +'%r') : Package map enabled"
        fi
    fi

    echo "\n$(date +'%r') : Populated install_media_ids.csv with file names and associated IDs"
    echo "$(date +'%r') : Opening install_media_ids.csv in default CSV viewer"
    open "${abs_dir}/install_media_ids.csv"
}

##############################################
# Populates values for custom apps and Self
# Service categories; calls Kandji API to get
# custom apps and Self Service categories
# Outputs:
#  Writes to package_map_values.csv
#  Opens package_map_values.csv in default CSV viewer
# Globals:
#  kandji_api
#  api_token
# Outputs:
#  Writes package_map_values.csv to disk
##############################################
function populate_values_for_map() {

    unset custom_apps ss_categories
    declare -a custom_apps ss_categories

    # Define API endpoints
    custom_apps_api="${kandji_api}/api/v1/library/custom-apps"
    self_service_api="${kandji_api}/api/v1/self-service/categories"
    retrieve_token "${kandji_token_name}"
    if [[ -z ${BEARER_TOKEN} ]]; then
        echo "$(date +'%r') : WARNING: Valid Kandji token not found!"
        if read -q "?Provide Kandji token now for mapping? (Y/N):"; then
            token_type="Kandji"
            assign_token_name
            prompt_for_secret
        else
            echo "\n$(date +'%r') : CRITICAL: Kandji token not found in ENV or keychain!"
            echo "$(date +'%r') : CRITICAL: Please provide a valid token when prompted\nAlternatively, run ./setup.command to populate your config"
            exit 1
        fi
    fi
    echo "$(date +'%r') : Populating available Custom Apps and Self Service categories..."
    echo "$(date +'%r') : Once package_map_values.csv is written, it will open in your default CSV viewer"
    echo "$(date +'%r') : Fill out package_map.json using values from created CSV"
    kandji_token=${BEARER_TOKEN}

    # Populate custom app and Self Service category arrays
    custom_apps_out=$(curl -s -L -X GET -H 'Content-Type application/json' -H "Authorization: Bearer ${kandji_token}" "${custom_apps_api}")
    ss_categories_out=$(curl -s -L -X GET -H 'Content-Type application/json' -H "Authorization: Bearer ${kandji_token}" "${self_service_api}")
    # Get counts of custom apps and Self Service categories for iteration
    custom_app_count=$(plutil -extract results raw -o - - <<< ${custom_apps_out})
    ss_category_count=$(plutil -convert raw -o - - <<< ${ss_categories_out})

    # Iterate through results, extract name, and append to array
    # shellcheck disable=SC2051
    for i in {0..$(( ${custom_app_count} - 1 ))}; do
        # shellcheck disable=SC2034
        custom_app_name=$(plutil -extract results.${i}.name raw -o - - <<< ${custom_apps_out})
        # Split on newline and append to array
        # shellcheck disable=SC2206
        custom_apps+=(${(f)custom_app_name})
    done

    # shellcheck disable=SC2051
    for i in {0..$(( ${ss_category_count} - 1 ))}; do
        # shellcheck disable=SC2034
        self_service_name=$(plutil -extract ${i}.name raw -o - - <<< ${ss_categories_out})
        # Split on newline and append to array
        # shellcheck disable=SC2206
        ss_categories+=("${(f)self_service_name}")
    done

    echo "\n$(date +'%r') : Found ${#custom_apps} Custom Apps and ${#ss_categories} Self Service categories"

    echo "Custom Apps,Self Service Categories" > "${abs_dir}/package_map_values.csv"
    # Get highest count of arrays to iterate through
    highest_count=$((${#ss_categories} > ${#custom_apps} ? ${#ss_categories} : ${#custom_apps}))
    # shellcheck disable=SC2051
    for i in {1..${highest_count}}; do
        echo "${custom_apps[i]},${ss_categories[i]}" >> "${abs_dir}/package_map_values.csv"
    done

    if [[ ${use_package_map} != true ]]; then
        echo "$(date +'%r') : Recipe map currently inactive"
        if read -q "?Enable it now? (from package_map.json) (Y/N):"; then
            plutil -replace use_package_map -bool true -r "${config_file}"
            use_package_map=true
            echo "$(date +'%r') : Recipe map enabled"
        fi
    fi

    echo "\n$(date +'%r') : Populated package_map_values.csv with Custom Apps and Self Service categories"
    echo "$(date +'%r') : Opening package_map_values.csv in default CSV viewer"
    open "${abs_dir}/package_map_values.csv"
}


##############################################
# Prompts to define periodic runtime in hours
# Validates assigned value is greater than 0
# Globals:
#   bc_frequency_hours_re
# Assigns:
#   periodic_hours
# Returns:
#   0 if assigned val is greater than 0
##############################################
function set_bc_freq() {

    value_regex_pattern=${bc_frequency_hours_re}
    prompt_for_value "how frequently cron brew should run (in hours)" "1 – 168"
    periodic_hours=${CONFIG_VALUE}

    if [[ ${periodic_hours} -gt 0 ]]; then
        echo "$(date +'%r') : kpkg brew cron will run every ${periodic_hours} hours"
        return 0
    else
        echo "\n$(date +'%r') : Provided value did not match expected sequence!"
        echo "$(date +'%r') : Number of hours should be greater than 0"
        echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
        prompt_for_value "how frequently cron brew should run (in hours)" "1 – 168"
    fi
}

##############################################
# Prompts to define a list of brew casks for
# runtime; strips quotes from input, converts
# commas to newlines, and assigns to array
# Confirms at least one cask assigned to arr
# Globals:
#   bc_casks_input_re
# Assigns:
#   casks
# Returns:
#   0 if # of assigned casks greater than 0
##############################################
function set_bc_casks() {
    value_regex_pattern=${bc_casks_input_re}
    prompt_for_value "brew casks which should run, comma-separated" "google-chrome,firefox,slack"
    casks_input=${CONFIG_VALUE}

    # Split input into array, removing any quotes
    casks=("${(f)$(tr -s ', ' '\n' <<< ${casks_input} | sed "s/^\([\"']\)\(.*\)\1\$/\2/g")}")
    if [[ ${#casks} -gt 0 ]]; then
        return 0
    else
        echo "\n$(date +'%r') : Provided value did not match expected sequence!"
        echo "$(date +'%r') : Cask names should be comma-separated and unquoted"
        echo "$(date +'%r') : Validate your input and try again; press CTRL+C to exit"
        prompt_for_value "brew casks which should run, comma-separated" "google-chrome,firefox,slack"
    fi
}

##############################################
# Creates and populates brew_cron.json config
# file with runtime frequency and cask names
# Globals:
#   bc_config_file
#   periodic_hours
#   casks
# Outputs:
#   Writes to brew_cron.json
##############################################
function create_populate_config() {
    plutil -create xml1 "${bc_config_file}"
    plutil -insert every_n_hours -integer ${periodic_hours} -r "${bc_config_file}"
    plutil -insert brew_casks -array -r "${bc_config_file}"
    # Sort casks reversed (O), with uniq values (u) and lowercase formatting (:l)
    for cask in "${(Ou)casks[@]:l}"; do
        plutil -insert brew_casks.0 -string ${cask} -r "${bc_config_file}"
    done
    plutil -convert json -r "${bc_config_file}"
}

##############################################
# Prompts user to create a new brew_cron.json
# config; exits with error if user declines
# Globals:
#   bc_config_file
# Returns:
#   Exit 1 if no valid config found
##############################################
function populate_brew_conf() {

    echo "$(date +'%r') : brew_cron.json config is missing or invalid"
    if read -q "?Create it now? (Y/N):"; then
        set_bc_freq
        set_bc_casks
        validate_casks
        create_populate_config
        echo "$(date +'%r') : Created ${bc_config_file}"
    else
        echo "\n$(date +'%r') : CRITICAL: Cannot continue without valid config! Exiting..."
        exit 1
    fi
}

##############################################
# Updates brew_cron.json config with provided
# cask names; confirms casks are valid
# Globals:
#   bc_config_file
##############################################
function update_brew_conf() {

    echo "$(date +'%r') : Will append provided values to brew_cron.json..."
    set_bc_casks
    validate_casks
    echo "$(date +'%r') : Adding above casks to ${bc_config_file}"
}

##############################################
# Reads brew_cron.json config; assigns to vars
# periodic runtime and casks once validated
# Globals:
#   bc_config_file
# Assigns:
#   casks (appends values to arr)
#   periodic_hours
##############################################
function read_brew_conf() {

    echo "$(date +'%r') : Reading config from ${bc_config_file}"

    # Get count of cask names
    # Minus 1 to account for 0-based index
    count=$(("$(plutil -extract brew_casks raw -o - "${bc_config_file}") - 1"))

    # Iter over all casks and append to arr
    # shellcheck disable=SC2051
    for i in {0..${count}}; do
        casks+=$(plutil -extract brew_casks.${i} raw -o - "${bc_config_file}")
    done
    validate_casks
    # Get runtime frequency (in hours)
    periodic_hours=$(plutil -extract every_n_hours raw -o - "${bc_config_file}")

}

##############################################
# Runs brew info on provided casks to confirm
# they are valid; exits with error if not
# Globals:
#   casks
# Returns:
#   Exit 1 if one or more brew casks invalid
##############################################
function validate_casks() {
    # Confirm all provided casks are valid according to Homebrew
    brew_out=$(brew info --quiet --casks "${(u)casks[@]}" 2>&1 1>/dev/null )
    if [[ $? -ne 0 ]]; then
        echo "\n$(date +'%r') : CRITICAL: One or more cask names were invalid:\n\n${brew_out}"
        exit 1
    fi
    echo "\n$(date +'%r') : Confirmed below casks are valid:\n\n${(ou)casks[@]}\n"
}

##############################################
# Converts casks arr into kpkg runtime string
# Converts periodic runtime into seconds
# Creates dir at ~/Library/LaunchAgents and
# creates/updates lagent plist in dir
# Globals:
#   casks
#   kpkg_brewcron
#   periodic_hours
#   sv_name
#   user_agents
# Outputs:
#   Writes LaunchAgent to user Library
##############################################
function create_bootstrap_agent() {

    # Format casks for kpkg (sort, unique, lowercase)
    kpkg_fmt_casks=$(printf ' -b %s' ${(ou)casks[@]:l})
    # Turn hours into seconds
    periodic_seconds=$((periodic_hours * 3600))

    mkdir -p "${user_agents}"

    /bin/cat > "${kpkg_brewcron}" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>${sv_name}</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
            </dict>
            <key>ProgramArguments</key>
            <array>
                <string>zsh</string>
                <string>-c</string>
                <string>/usr/local/bin/kpkg${kpkg_fmt_casks}</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>${periodic_seconds}</integer>
        </dict>
    </plist>
EOF
}

##############################################
# Attempts to bootout LaunchAgent and reports
# status; if lagent plist exists, removes it
# Otherwise, warns that file not found
# Globals:
#   kpkg_brewcron
#   sv_name
#   uid
# Outputs:
#   Unloads and removes LaunchAgent from disk
##############################################
function bootout_remove_agent() {
    if ! launchctl bootout "gui/${uid}/${sv_name}" 2>/dev/null; then
        echo "$(date +'%r') : WARNING: Service not loaded at gui/${uid}/${sv_name}"
    else
        echo "$(date +'%r') : Successfully stopped service gui/${uid}/${sv_name}"
    fi
    if [[ -f "${kpkg_brewcron}" ]]; then
        rm -f "${kpkg_brewcron}"
        echo "$(date +'%r') : Successfully removed ${kpkg_brewcron}"
    else
        echo "$(date +'%r') : WARNING: ${kpkg_brewcron} not found"
    fi
}

##############################################
# Sets permissions on LaunchAgent and attempts
# to bootstrap; if unsuccessful, retries once
# Prints command to monitor log if desired
# Globals:
#   kpkg_brewcron
#   sv_name
#   uid
# Arguments:
#   retry; ${1} (bool)
# Outputs:
#   Updates perms and loads LaunchAgent
# Returns:
#   Exit 1 if agent bootstrap fails twice
##############################################
function agent_perms_load() {

    retry=${1}

    chmod 644 "${kpkg_brewcron}"
    chown ${user}:staff "${kpkg_brewcron}"
    echo "$(date +'%r') : Wrote service with above casks scoped to ${kpkg_brewcron}"
    if ! launchctl bootstrap "gui/${uid}" "${kpkg_brewcron}" >/dev/null 2>&1; then
        launchctl bootout "gui/${uid}/${sv_name}" && launchctl bootstrap "gui/${uid}" "${kpkg_brewcron}"
    fi
    if launchctl print "gui/${uid}/${sv_name}" >/dev/null 2>&1; then
        echo "$(date +'%r') : Successfully bootstrapped ${kpkg_brewcron} — service is now active"
        echo "$(date +'%r') : Run the following to monitor progress (CTRL+C to quit):\ntail -f ~/Library/KandjiPackages/kpkg.log"
    elif ! ${retry}; then
        echo "$(date +'%r') : WARNING: Unable to bootstrap ${kpkg_brewcron}... Trying once more"
        agent_perms_load true
    else
        echo "$(date +'%r') : ERROR: Unable to bootstrap ${kpkg_brewcron} (tried twice)... Exiting"
        exit 1
    fi
}

##############################################
# Checks config; assigns name of Kandji token
# and optional Slack token; if Kandji token
# undefined in config, returns 1 for err
# Validates defined tokens are placed in
# designated keystore(s) and if not found,
# prompts interactively for user to populate
# Globals:
#   config_file
# Assigns:
#   token_type
#   kandji_token_name
#   slack_token_name
##############################################
# shellcheck disable=SC2120
function main() {

    if [[ "${EUID}" -eq 0 ]]; then
        echo "$(date +'%r') : kpkg-setup should NOT be run as superuser! Exiting..."
        exit 1
    fi

    format_stdout "Kandji Packages (kpkg) Setup (${version})"
    # Check opts array to ensure no arguments are passed in
    if [[ -z $(printf '%s\n' "${(@)opts}") ]]; then
        # No args is default program
        format_stdout "kpkg Initial Setup"
    fi

    ######################
    # kpkg Brew Cron
    ######################
    # Ensure any passed -a/-u flags are used with -b
    if [[ -n $(printf '%s\n' "${(@)opts}" | grep -- '-a\|-u') ]] && [[ -z $(printf '%s\n' "${(@)opts}" | grep -- '-b') ]]; then
        echo "$(date +'%r') : ERROR: Invalid flag combination: -b must be specified alongside -a/-u"
        exit 1
    elif [[ $(printf '%s\n' "${(@)opts}" | grep -c -- '-a\|-u') -ge 2 ]]; then
        echo "$(date +'%r') : ERROR: Invalid flag combination: -a and -u cannot be passed together"
        exit 1
    fi

    if (( ${opts[(I)(-b|--brewcron)]} )); then
        if (( ${opts[(I)(-u|--uninstall)]} )); then
            format_stdout "kpkg Brew Cron Uninstallation"
            bootout_remove_agent
            exit 0
        fi
        format_stdout "kpkg Brew Cron Starting"
        if ! brew --version >/dev/null 2>&1; then
            echo "$(date +'%r') : ERROR: Confirm Homebrew is installed/available in PATH and try again..."
            exit 1
        fi
        if ! plutil -type brew_casks "${bc_config_file}" >/dev/null 2>&1; then
            populate_brew_conf
        else
            if (( ${opts[(I)(-a|--addcask)]} )); then
                update_brew_conf
            fi
            read_brew_conf
            create_populate_config
        fi
        create_bootstrap_agent
        agent_perms_load false
        format_stdout "kpkg Brew Cron Complete"
        exit 0
    fi

    # Read in config and assign values to vars
    read_config

    ######################
    # kpkg Install ID
    ######################
    if (( ${opts[(I)(-i|--idfind)]} )); then
        format_stdout "kpkg Install ID Lookup Starting"
        prompt_validate_pkg_pkgs
        format_stdout "kpkg Install ID Lookup Complete"
        exit 0
    fi

    ######################
    # kpkg Mapping
    ######################
    if (( ${opts[(I)(-m|--map)]} )); then
        format_stdout "kpkg Mapping Starting"
        populate_values_for_map
        format_stdout "kpkg Mapping Complete"
        exit 0
    fi

    ######################
    # kpkg Reset
    ######################
    if (( ${opts[(I)(-r|--reset)]} )); then
        format_stdout "kpkg Reset Starting"
        reset_kandji_url=false
        reset_keystore=false
        reset_kandji_token=false
        reset_slack_token=false
        reset_values
        format_stdout "kpkg Reset Complete"
        exit 0
    fi

    ######################
    # kpkg Config Only
    ######################
    # If flag is set for config-only, don't offer to store secrets
    if (( ${opts[(I)(-c|--config)]} )); then
        format_stdout "kpkg Config Only"
        config_only=true
    else
        config_only=false
    fi

    # Run prechecks to validate config file and on-disk
    prechecks

    format_stdout "kpkg Setup Complete"
}

###############
##### MAIN ####
###############

main
