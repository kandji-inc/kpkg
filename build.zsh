#!/bin/zsh 
# Created 03/14/24; NRJA
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

##############################
########## VARIABLES #########
##############################

# Get local dir name
dir=$(dirname ${ZSH_ARGZERO})
version_path="${dir}/VERSION"
version=$(cat "${version_path}")
identifier="io.kandji.kpkg"
py_pkg_fallback="https://www.python.org/ftp/python/3.12.2/python-3.12.2-macos11.pkg"
# Create sandbox
tmp_dir=$(mktemp -d)
py_pkg_path="${tmp_dir}/py3.pkg"
expanded_py="${tmp_dir}/expanded_py"
expanded_py_fw_pkg="${expanded_py}/Python_Framework.pkg"
kpkg_out="${tmp_dir}/kpkg_dist"
venv_dir="${tmp_dir}/pyvenv"
venv_bin="${venv_dir}/bin"
activate_bin="${venv_bin}/activate"
vpip_bin="${venv_bin}/pip3"
vpyi_bin="${venv_bin}/pyinstaller"
py_url="https://www.python.org/getit"

##############################
########## FUNCTIONS #########
##############################

##############################################
# Sources the universal2 Python3 installer PKG
# since we cannot rely on local Py being U2
##############################################
function download_expand_py() {
    # Grab the latest version of Python3 by PKG
    if [[ ! -f "${py_pkg_path}" ]]; then
        echo "Downloading Python3 PKG..."
        py_pkg_url=$(curl -s -L --compressed "${py_url}" 2>&1 | /usr/bin/grep -i pkg | /usr/bin/xargs | /usr/bin/awk -F 'href=|>Download' '{print $2}')
        if [[ -z ${py_pkg_url} ]]; then
            echo "WARNING: Unable to determine Python PKG download URL from source ${py_url}"
            echo "Assigning from fallback URL..."
            py_pkg_url="${py_pkg_fallback}"
        fi
        curl -s -L "${py_pkg_url}" -o "${py_pkg_path}"
    fi
    pkgutil --expand-full "${py_pkg_path}" "${expanded_py}"
    py_bin=$(find ${expanded_py_fw_pkg} -name python3)
    # Get Py vers dir
    py_pkg_fw=$(find ${expanded_py_fw_pkg} -maxdepth 3 -type d -path '*Versions/*')
}

##############################################
# Validates Python3 framework dylib path and
# creates symlink if necessary to make Python
# frameworks accessible to system library path
##############################################
function validate_py_health() {
    did_link=false
    py_framework_check=$(${py_bin} -V 2>&1 | grep "Library not loaded")

    if [[ -n ${py_framework_check} ]]; then
        echo "Creating symlink for framework... (requires sudo)"
        lib_fw_full_py_path=$(cut -d ':' -f3 <<< ${py_framework_check} | xargs)
        lib_fw_py_path=${lib_fw_full_py_path%/*/*}
        sudo mkdir -p ${lib_fw_py_path}
        linked_path=$(sudo ln -v -s ${py_pkg_fw} ${lib_fw_py_path} | awk '{print $1}')
        did_link=true
    fi

    if ! ${py_bin} -V >/dev/null 2>&1; then
        echo "Python3 still could not be loaded after setting dylib path... Exiting"
        exit 1
    fi
}

##############################################
# Sets up Python3 venv, installs pyinstaller,
# requests, and older charset_normalizer
# (older vers needed to allow U2 build)
# Builds kpkg.py with pyinstaller, renames,
# and zips up the output, moving to dir
##############################################
function py_env_setup_build() {
    echo "Setting up Python3 venv and building kpkg..."
    ${py_bin} -m venv "${venv_dir}"
    # shellcheck disable=SC1090
    source ${activate_bin}
    ${vpip_bin} -qq install pyinstaller requests "charset_normalizer<3.0"
    ${vpyi_bin} -y --log-level ERROR --target-arch universal2 --add-data "${version_path}":"." --contents-directory ".kpkg_py_framework" --distpath "${kpkg_out}" -n "kpkg" ${dir}/kpkg.py
    deactivate
    pushd "${kpkg_out}" || exit
    mv "./kpkg" "./KandjiPackages"
    zip -q -r "./kpkg.zip" "./KandjiPackages"
    popd || exit
    mv "${kpkg_out}/kpkg.zip" "${dir}"
    echo "KPKG build complete"
}

##############################################
# DLs + installs Xcode Command Line Tools
# Outputs:
#   Installs Xcode Command Line Tools on disk
# Returns:
#   Success, else exit 1 and notify on error
##############################################
function xcode_clt_install() {

    # Create hidden temp file to enable Xcode CLT install from softwareupdate
    xclt_tmp="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
    /usr/bin/touch "${xclt_tmp}"

    # Grab exact name for CLT
    cmd_line_tools=$(/usr/sbin/softwareupdate -l | /usr/bin/awk '/\*\ Label: Command Line Tools/ { $1=$1;print }' | /usr/bin/sed 's/^[[ \t]]*//;s/[[ \t]]*$//;s/*//' | /usr/bin/cut -c 9-)

    # Find latest returned Xcode CLT if more than one present
    if (( $(/usr/bin/grep -c . <<<"${cmd_line_tools}") > 1 )); then
        cmd_line_tools_output="${cmd_line_tools}"
        cmd_line_tools=$(printf "${cmd_line_tools_output}" | /usr/bin/tail -1)
    fi

    # Install it
    /usr/sbin/softwareupdate -i "${cmd_line_tools}" --verbose

    # Validate success
    exit_code=$?

    if [[ "${exit_code}" == 0 ]]; then
        echo "Successfully installed Xcode Command Line Tools"
    else
        echo "Xcode Command Line Tools failed to install with exit code ${exit_code}"
        exit 1
    fi

    # Remove temp file
    /bin/rm "${xclt_tmp}"
}

##############################################
# Checks for lipo binary, prompts user to
# install Xcode CLT if not present
##############################################
function lipo_check() {
    if ! lipo -info /usr/bin/lipo >/dev/null 2>&1; then
        echo "lipo not installed — attempting Xcode CLT install"
        xcode_clt_install
    fi
}

##############################################
# Writes postinstall script via heredoc to be
# bundled with kpkg installer; postinstall
# script unzips kpkg.zip, moves files to
# expected location in user's Library, and
# symlinks kpkg/kpkg-setup to /usr/local/bin
# Adds /usr/local/bin to user's PATH if not
# already set and reinforces user ownership
##############################################
function write_postinstall() {

    /bin/cat > "${dir}/Scripts/postinstall" <<"EOF"
#!/bin/zsh -f

user=$(stat -f%Su /dev/console)
user_dir=$(dscl /Local/Default -read "/Users/${user}" NFSHomeDirectory | /usr/bin/cut -d ":" -f2 | /usr/bin/xargs)

mkdir -p "${user_dir}/Library/KandjiPackages"
unzip -o "/tmp/kpkg.zip" -d "${user_dir}/Library"

rm -f "${user_dir}/Library/KandjiPackages/"{setup.zsh,audit_app_and_version.zsh}

mv -n "/tmp/"{setup.zsh,package_map.json,config.json,audit_app_and_version.zsh} "${user_dir}/Library/KandjiPackages"
chown -f -R "${user}" "${user_dir}/Library/KandjiPackages"
mkdir -p "/usr/local/bin"
ln -f -s "${user_dir}/Library/KandjiPackages/kpkg" "/usr/local/bin/kpkg"
ln -f -s "${user_dir}/Library/KandjiPackages/setup.zsh" "/usr/local/bin/kpkg-setup"
rm -f "/tmp/kpkg.zip"

path_check=$(tr ':' '\n' <<< $(su - "${user}" -c "printenv PATH") | grep -o '^/usr/local/bin$')
if [[ -z ${path_check} ]]; then
    user_shell=$(dscl . -read /Users/${user} UserShell | cut -d ":" -f2)
    if grep -q -i zsh <<< ${user_shell}; then
        dotfile_name=".zshrc"
    elif grep -q -i bash <<< ${user_shell}; then
        dotfile_name=".bashrc"
    else
        dotfile_name=".profile"
    fi
    echo "/usr/local/bin not found in user path — adding to ${dotfile_name}..."
    export PATH=${PATH}:/usr/local/bin
    echo 'export PATH=${PATH}:/usr/local/bin' >> "${user_dir}/${dotfile_name}"
    chown -f "${user}" "${user_dir}/${dotfile_name}"
fi

exit 0
EOF

    # Make executable
    chmod a+x "${dir}/Scripts/postinstall"
}

##############################################
# Builds kpkg.pkg with pkgbuild, using Payload
# folder to store kpkg.zip/assorted scripts
# and postinstall script in Scripts folder
# Prints .pkg location to stdout once built
##############################################
function build_kpkg_pkg() {

    # Clean up previous Payload folder if present
    rm -fR "${dir}/Payload" "${dir}/Scripts"

    mkdir -p "${dir}/Payload/tmp" "${dir}/Scripts"

    # Write postinstall script to dir
    write_postinstall

    # Copy kpkg.zip and assorted scripts to Payload
    cp -R "${dir}/"{kpkg.zip,setup.zsh,package_map.json,config.json,audit_app_and_version.zsh} "${dir}/Payload/tmp"

    echo "Creating kpkg-${version}.pkg"
    if [[ $(uname) == "Darwin" ]]; then
        /usr/bin/pkgbuild --quiet --root "${dir}/Payload" --scripts "${dir}/Scripts" --identifier "${identifier}" --version ${version} "${dir}/kpkg-${version}.pkg"
    fi
    echo "Successfully built ${dir}/kpkg-${version}.pkg"
}

##############################################
# Cleans up temporary files and symlinks
# as well as folders used in build process
##############################################
function cleanup() {
    if ${did_link}; then
        echo "Removing temporary symlink for framework... (requires sudo)"
        sudo unlink ${linked_path} 2>/dev/null
    fi
    rm -f -R ${tmp_dir}
    # Clean up Payload folder post-build
    rm -fR "${dir}/Payload" "${dir}/Scripts" "${dir}/build" "${dir}/kpkg.spec" "${dir}/kpkg.zip"
}

##############################################
# Main runtime to download Universal2 Python3
# PKG, expand, validate, setup venv, install
# pyinstaller, build kpkg, and clean up
#############################################
function main() {

    pushd "${dir}" || exit
    download_expand_py
    validate_py_health
    lipo_check
    py_env_setup_build
    build_kpkg_pkg
    cleanup
    popd || exit
}

###############
##### MAIN ####
###############
main
