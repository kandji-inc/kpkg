## v.1.1.0
---
#### **Features**:
- Added new functionality to configure/create a background service (macOS LaunchAgent) to periodically execute `kpkg -b` against a list of brew casks
  - **kpkg Brew Cron** enables recurring Homebrew cask checks, automatically uploading/deploying new versions to Kandji
  - Initial configuration and service can be created by running `kpkg-setup -b`; see [updated README documentation](README.md#brew-cron) for more detail
#### **Bug fixes**:
- Improved error handling/response when a required token is invalid/missing
- Improved HTTP status code handling for Kandji API responses
- Improved secrets population in ENV to update an existing token entry when running a reset
- Resolved a rare issue where Slack webhook validation could fail during initial setup
#### **Miscellaneous**:
- Improved dynamic naming for Kandji custom apps to filter out versions detected in installer media

## v.1.0.2
---
#### **Features**:
- Added shasum comparison for pending uploads and existing apps, skipping installer upload/Library Item update if `sha256` hashes match
#### **Bug fixes**:
- Resolved an issue where certain `.pkg` values were assigned out of order with package mapping enabled
- Resolved an issue where a false positive was erroneously logged when a matching map value was not found
#### **Miscellaneous**:
- Modified order in which upload occurs so certain create/update checks run first
- Added `-f` flag (equivalent to `--no-rcs`) to `#!/bin/zsh` in `audit_app_and_version.zsh` and installer `postinstall`
  - This suppresses the evaluation/execution of user `zsh` dotfiles during runtime

## v.1.0.1
---
#### **Bug fixes**:
- Resolved an issue where a config-defined Self Service category missing in Kandji caused an error
- Resolved an issue cleaning up a mounted `.dmg` at the end of runtime
#### **Miscellaneous**:
- Added new GH templates for feature requests and bug reports

## v.1.0.0
---
### INITIAL RELEASE
- Initial release of Kandji Packages!
- [See here](README.md) for more detail
