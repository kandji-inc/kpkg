# Kandji Packages (`kpkg`)

Standalone tool for programmatic management of Kandji Custom Apps

## Table of Contents
- [About](#about)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Usage](#usage)
- [Configuration Options](#configuration-options)
  - [Kandji Packages Config](#kpkg-config)
  - [Command Line Flags](#command-line-flags)
  - [Package Map](#package-map)
- [Runtime Considerations](#runtime-considerations)
  - [Supported Custom Apps](#supported-custom-apps)
  - [Enforcements](#enforcements)
  - [Custom App Behavior](#custom-app-behavior)
- [Technical Details](#technical-details)
  - [Secrets Management](#secrets-management)
  - [Kandji Token Permissions](#kandji-token-permissions)
  - [Slack Token Setup](#slack-token-setup)
  - [config.json](#configjson)
  - [package_map.json](#package_mapjson)
  - [kpkg Flags](#kpkg-flags)
  - [kpkg-setup Flags](#kpkg-setup-flags)
  - [Audit/Enforcement Examples](#audit-enforcement-examples)

## About
A command-line tool designed for programmatic management of Kandji Custom Apps

Configurable in a variety of ways, Kandji Packages can be used to create, update, and enforce Custom Apps in Kandji

Fully open source, we welcome contributions and feedback to improve the tool!

## Prerequisites
Before running Kandji Packages, ensure you have the following:

- Kandji API token ([required permissions](#kandji-token-permissions))
- Slack webhook token (optional; [setup instructions](#slack-token-setup))

## Initial Setup

1. [Click here](https://github.com/kandji-inc/kpkg/releases/latest) to download the latest `.pkg` release
2. Right-click the downloaded `.pkg`, select `Open`, and follow the installation prompts
3. Once installed, open Terminal and run `kpkg-setup` to interactively set required parameters (written to `config.json`)
 - **Kandji API URL** (`TENANT.api.[eu.]kandji.io`)
 - **Secrets keystore selection** (ENV and/or user's login keychain)
 - **Kandji bearer token**
 - **Slack webhook token** (optional)

> [!TIP]
> Set `ENV` values for `KANDJI_API_URL` (`str`) and `ENV_KEYSTORE` (`bool`) to override their settings in `config.json`

[See below](#kpkg-setup-flags) for available `kpkg-setup` flags

## Usage

`kpkg` and `kpkg-setup` are the two Kandji Packages binaries

`kpkg` is the main executable, and must be called with one of two required flags: `-p`/`-b`
  - `-p` accepts a local path to a valid `.pkg` or `.dmg` for upload
  - `-b` accepts a Homebrew cask name; `brew` download must be a valid `.pkg` or `.dmg` for upload

### Examples

#### Uploading to Kandji from existing download:

- Download the latest Google Chrome installer [here](https://dl.google.com/dl/chrome/mac/universal/stable/gcem/GoogleChrome.pkg)
- Run `kpkg -p /path/to/downloaded/GoogleChrome.pkg`
- If the package is not found in Kandji, Kandji Packages will create a new Custom App
- If the package is found (by name), Kandji Packages will update the existing Custom App

```
2024-04-15 04:40:17 PM [MacBook Pro]: INFO: Processing 'GoogleChrome.pkg'
2024-04-15 04:40:19 PM [MacBook Pro]: INFO: Located matching map value 'com.google.Chrome' from PKG/DMG
2024-04-15 04:40:19 PM [MacBook Pro]: INFO: Beginning file upload of 'GoogleChrome.pkg'...
2024-04-15 04:41:09 PM [MacBook Pro]: INFO: Successfully uploaded 'GoogleChrome.pkg'!
2024-04-15 04:41:09 PM [MacBook Pro]: INFO: Searching for 'Google Chrome (GA)' from list of custom apps
2024-04-15 04:41:09 PM [MacBook Pro]: WARNING: (HTTP 503): The upload is still being processed.
2024-04-15 04:41:09 PM [MacBook Pro]: INFO: Retrying in five seconds...
2024-04-15 04:41:14 PM [MacBook Pro]: INFO: Searching for 'Google Chrome (GA)' from list of custom apps
2024-04-15 04:41:15 PM [MacBook Pro]: INFO: SUCCESS: Custom App Update
2024-04-15 04:41:15 PM [MacBook Pro]: INFO: Custom App 'Google Chrome (GA)' available at 'https://accuhive.kandji.io/library/custom-apps/1436cf21-a777-49c4-8e4c-386ca3107a9a'
2024-04-15 04:41:15 PM [MacBook Pro]: INFO: Successfully posted message to Slack channel
2024-04-15 04:41:15 PM [MacBook Pro]: INFO: Searching for 'Google Chrome (Patch Testers)' from list of custom apps
2024-04-15 04:41:16 PM [MacBook Pro]: INFO: SUCCESS: Custom App Update
2024-04-15 04:41:16 PM [MacBook Pro]: INFO: Custom App 'Google Chrome (Patch Testers)' available at 'https://accuhive.kandji.io/library/custom-apps/e2c2b6ce-da42-4b54-9f85-2abfaf8f4274'
2024-04-15 04:41:16 PM [MacBook Pro]: INFO: Successfully posted message to Slack channel
```
|<img src="https://github.com/kandji-inc/support/assets/27963671/23123c99-b9ba-4286-afec-87852928a5bf" width="400">|
|:-:|
|Slack notifications sent to channel from local run|

#### Uploading to Kandji, sourcing/downloading updates from Homebrew

- Ensure Homebrew is installed on-disk with `brew` available in your `PATH`
  - If not installed, download the [latest installer package here](https://github.com/Homebrew/brew/releases/latest)
- Recommend running `brew search --casks CASK` to confirm the correct cask name

```
➜  ~ brew search --casks googlechrome
==> Casks
google-chrome
```
- Run `kpkg -b CASK`
- Will use local download if present, otherwise fetches from Homebrew
- Same as above, if found in Kandji, will update the existing Custom App, else creates new

```
2024-04-15 04:39:34 PM [MacBook Pro]: INFO: brew fetching 'coteditor'...
2024-04-15 04:39:36 PM [MacBook Pro]: INFO: Downloaded 'coteditor' to '/Users/noah/Library/Caches/Homebrew/downloads/2f159e4270397f68161b6a891ab35a32085f02dbfef6c61191251ccd0278e2eb--CotEditor_4.7.4.dmg'
2024-04-15 04:39:36 PM [MacBook Pro]: INFO: Processing '2f159e4270397f68161b6a891ab35a32085f02dbfef6c61191251ccd0278e2eb--CotEditor_4.7.4.dmg'
2024-04-15 04:39:37 PM [MacBook Pro]: INFO: Located matching map value 'com.coteditor.CotEditor' from PKG/DMG
2024-04-15 04:39:38 PM [MacBook Pro]: INFO: Beginning file upload of '2f159e4270397f68161b6a891ab35a32085f02dbfef6c61191251ccd0278e2eb--CotEditor_4.7.4.dmg'...
2024-04-15 04:39:45 PM [MacBook Pro]: INFO: Successfully uploaded '2f159e4270397f68161b6a891ab35a32085f02dbfef6c61191251ccd0278e2eb--CotEditor_4.7.4.dmg'!
2024-04-15 04:39:45 PM [MacBook Pro]: INFO: Searching for 'CotEditor (Testing)' from list of custom apps
2024-04-15 04:39:45 PM [MacBook Pro]: WARNING: (HTTP 503): The upload is still being processed.
2024-04-15 04:39:45 PM [MacBook Pro]: INFO: Retrying in five seconds...
2024-04-15 04:39:50 PM [MacBook Pro]: INFO: Searching for 'CotEditor (Testing)' from list of custom apps
2024-04-15 04:39:51 PM [MacBook Pro]: INFO: SUCCESS: Custom App Update
2024-04-15 04:39:51 PM [MacBook Pro]: INFO: Custom App 'CotEditor (Testing)' available at 'https://accuhive.kandji.io/library/custom-apps/80db3b94-0a9c-4dfc-8191-6c982141a7e6'
2024-04-15 04:39:51 PM [MacBook Pro]: INFO: Successfully posted message to Slack channel
```
|<img src="https://github.com/kandji-inc/support/assets/27963671/3b0971d7-70a5-42dd-809c-98b658915f8a" width="600">|
|:-:|
|Slack notifications sent to channel from brew run|

---

## Configuration Options

Kandji Packages supports both runtime flags and centralized options for customizing your PKG/DMG --> Kandji workflow

Configuration files are stored in `~/Library/KandjiPackages`

### Kandji Packages Config

- `config.json` includes defaults if no per-recipe settings are found
  - Config can be modified as desired to set preferred defaults
  - [See below](#config.json) for an overview of available options and a sample config

### Command Line Flags

- `kpkg` accepts optional args to set/override the following:
  - Always create new Custom App
  - Dry run of Kandji Packages (do not modify Kandji)
  - Custom app name
  - Custom app name (test)
  - Self Service category
  - Self Service category (test)
  - [See below](#kpkg-flags) for detailed usage instructions

> [!NOTE]
> If multiple configuration types are set during runtime, those passed via command line supersede any mappings

### Package Map

- A package map (`package_map.json`) can be defined to associate packages by ID to Kandji Custom Apps
  - Key is the package ID
    - Run `kpkg-setup -i` to identify the package ID for one or multiple `.pkg`s (also accepts `.dmg`s)
    - [See below](#kpkg-setup-flags) for full usage instructions for `kpkg-setup`
  - Below values can be defined in-map:
    - Custom app name (`prod_name`)
    - Custom app name (test) (`test_name`)
    - Self Service category (`ss_category`)
    - Self Service category (test) (`test_category`)
  - [See below](#package_map.json) for a sample config

> [!TIP]
> Running `kpkg-setup -m` exports a .csv containing Custom App names and Self Service categories to help populate `package_map.json`

## Runtime Considerations

### Supported Custom Apps
- Currently, both installer packages and disk images are supported by this project
  - Packages include flat, component, and distribution types (`.pkg`/`.mpkg`)
  - Disk image contents may include `.app` or `.pkg` (`.dmg`)
- Based on interest, new features may be considered and added over time
  - We would also welcome contributions!
- `.pkg`/`.dmg` uploads can be configured with any Kandji enforcement type (see below)
  - This includes installers whose payloads are app bundles (`.app`) or command line tools/binaries
    - Audit/enforcement criteria are determined from:
      - An app bundle's `Info.plist`
      - A binary's installer package metadata (must contain version)

### Enforcements
- Kandji Packages supports three enforcement types (configurable in `config.json`), which sets enforcement type for new Custom Apps:
  - `audit_enforce` (Default)
  - `install_once`
  - `self_service`
- When updating _existing_ Custom Apps, Kandji Packages will respect the enforcement type already set in Kandji
- If method can't be read from `config.json`, enforcement defaults to `install_once`

> [!NOTE]
> When a Self Service category is defined via command line/map, enforcement is automatically set to `self_service` (ignoring `config.json`) during new app creation

#### `audit_enforce`
- Setting `audit_enforce` bundles `audit_app_and_version.zsh` for the Custom App's Audit Script during creation
  - App name, identifier, and version details are automatically populated in the audit script prior to upload
  - Subsequent updates to apps with audit enforcement receive an updated audit script with latest app info, version, and enforcement dates
- Up to two Custom App names can be specified (via command line or map), one for production workflows (`prod_name`) and the other for testing (`test_name`)
  - Production defaults to **5 days** prior to enforcement, with testing set to **0 days** (immediate enforcement)
    - Days until enforcement values are configurable in `config.json`
  - If `audit_enforce` is set but no values provided for `prod_name` or `test_name`, Kandji Packages still uses the prod delay set in `config.json`
    - If delay values are removed from `config.json`, Kandji Packages will fall back to an enforcement delay of **3 days**
- [See below](#audit-enforcement-example-output) for Kandji audit/enforcement output examples
- If enforcement is due, but the app in use by the user, the user will be prompted to close the app, else delay one hour
![Delay Available](https://github.com/kandji-inc/support/assets/27963671/c74148c5-5e8e-4673-a04e-e2ef480604f7)
- Once the delay has lapsed, the user will again be prompted to quit, but with no delay option
![Enforcement Due](https://github.com/kandji-inc/support/assets/27963671/8c4496ae-1c82-4297-a5c2-f0dc616c4f39)

> [!CAUTION]
> `audit_app_and_version.zsh` immediately installs the custom app if not found on-disk!
>
> Otherwise, waits until deadline to validate installed version matches or exceeds the enforced

#### `self_service`
- With `self_service` enforcement, it is recommended to define a category via command line/map for `ss_category` (accompanying `prod_name`)
  - If not, will fall back to defined `self_service_category` (Default: `Apps`)
- Test workflows can be used with Self Service, but also recommend defining `test_category` (accompanying `test_name`)
  - Otherwise, falls back to `test_self_service_category` (Default: `Utilities`)
    - Default Self Service categories are configurable in `config.json`

[See here](https://support.kandji.io/support/solutions/articles/72000558748-custom-apps-overview) for more information regarding Kandji Custom App enforcement

### Custom App Behavior

#### New Custom Apps
- If no value is provided for `custom_app.prod_name` in recipe/override XML, the naming convention will be taken from the `config.json` default

#### Dynamic Lookup
- Kandji Packages supports dynamic lookup, used as a fallback if a definitive Custom App cannot be found by name
  - Configurable in `config.json` under `zz_defaults.dynamic_lookup`
- Lack of definitive Custom App includes both matching duplicates (by name) as well as when no matches are found
  - For duplicates by name, if dynamic lookup is disabled, duplicates are posted to Slack with metadata (creation date, etc.)
  - For no matches by name, if dynamic lookup is disabled, Kandji Packages will create a new entry if so configured, otherwise exit
- During dynamic lookup, Kandji Packages detects all existing Custom App PKGs and identify any that are similar by name to the provided installation media (PKG/DMG)
  - Of those, the highest version(s) will be detected from the PKG/DMG name (given standard formatting NAME-VERSION.pkg)
  - If multiple highest versions are detected (compared via semantic version), the oldest Custom App by last modification is selected for update

> [!CAUTION]
> Dynamic lookup will replace a Custom App's previous package without confirmation!
>
> This may have unintended impact, so recommend first testing with dry run enabled (`-y`)

## Technical Details

### Secrets Management
- Kandji Packages supports two keystore options for storing tokens:
  - `environment` variables (`ENV`)
    - During `kpkg-setup`, secret storage in the user's dotfile is determined from the default shell; `UserShell` from `dscl`
    - For `zsh`, `.zshenv` is used; for `bash`, `.bash_profile`; otherwise, `.profile`
    - If setting `ENV` programmatically for runtime, ensure `ENV_KEYSTORE` is set to `true` to enable ENV keystore
  - macOS login keychain (for console user)
    - During `kpkg-setup`, keychain source is determined from `/usr/bin/security login-keychain`
    - Running either `kpkg-setup` or `kpkg` may prompt the user to unlock the keychain if locked before continuing

> [!CAUTION]
> Recommended use of this tool is on a Privileged Access Workstation/Hardened Device, accessible only to authorized users
>
> Storing secrets on-disk always poses some risk, so ensure proper security measures are in place


### Kandji Token Permissions

Configure your Kandji bearer token to include the following scope:

- <ins>**Library**</ins>
  - `Create Custom App`
  - `Upload Custom App`
  - `Update Custom App`
  - `List Custom Apps`
  - `Get Custom App`
- <ins>**Self Service**</ins>
  - `List Self Service Categories`

Instructions for creating a Kandji API token [can be found here](https://support.kandji.io/support/solutions/articles/72000560412-kandji-api)

### Slack Token Setup

- Instructions for per-channel webhook generation can be [found here](https://api.slack.com/messaging/webhooks)
  - Webhook should be in the form `https://hooks.slack.com/services/XXXXXXXXX/XXXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX`

### config.json

#### Required Keys
| Required Key          | Accepted Values            | Description                                                         | Default |
|-----------------------|----------------------------|---------------------------------------------------------------------|-------|
| `kandji.api_url`      | `TENANT.api.[eu.]kandji.io`   | Valid Kandji URL for API requests                                      |  |
| `kandji.token_name`   | *Name of Kandji token in keystore* | Name of Kandji token stored in keystore                              |`KANDJI_TOKEN`|
| `li_enforcement.type`    | `audit_enforce`\|`install_once`\|`self_service`| Default enforcement type if no override specified | `audit_enforce` |
| `slack.enabled`        |`bool`<br />               | Toggle on/off Slack notifications for runtime | `true` |
| `slack.webhook_name`        | *Name of Slack token in keystore* | Token name with value `hooks.slack.com/services` | `SLACK_TOKEN` |
| `token_keystore`      | **`environment:`**`bool`<br />**`keychain:`**`bool` | Keystore source(s) to retrieve tokens | `false` <br /> `false` |
| `use_package_map`      | `bool`                      | Use recipe --> Kandji mapping from `package_map.json`       | `false` |

#### Optional Keys
| Optional Key          | Accepted Values            | Description                                                         | Default |
|-----------------------|----------------------------|---------------------------------------------------------------------|---------|
| `li_enforcement.delays`  | **`prod:`**`int`<br />**`test:`**`int` | Number of days before app/version enforcement occurs | `5`<br /> `0`
| `zz_defaults.auto_create_app` | `bool`                      | If custom app cannot be found to update, create new         | `true`         |
| `zz_defaults.dry_run` | `bool`                      | Does not modify any Kandji Custom Apps; shows instead what would have run | `false`         |
| `zz_defaults.dynamic_lookup`| `bool`                   | If custom app cannot be found to update, dynamically search and select | `false` |
| `zz_defaults.new_app_naming`      | `str`                       | Custom app naming convention if the name isn't otherwise specified   | `APPNAME (AutoPkg)` |
| `zz_defaults.self_service_category`| `str`                      | Self Service Category for `prod_name` if not otherwise specified          | `Apps` |
| `zz_defaults.test_self_service_category` | `str`               | Self Service Category for `test_name` if not otherwise specified     | `Utilities` |

#### Example config.json
```json
{
  "kandji" : {
    "api_url" : "TENANT.api.kandji.io",
    "token_name" : "KANDJI_TOKEN"
  },
  "li_enforcement" : {
    "delays" : {
      "prod" : 5,
      "test" : 0
    },
    "type" : "install_once"
  },
  "slack" : {
    "enabled" : true,
    "webhook_name" : "SLACK_TOKEN"
  },
  "token_keystore" : {
    "environment" : false,
    "keychain" : false
  },
  "use_package_map" : false,
  "zz_defaults" : {
    "auto_create_new_app" : true,
    "dry_run" : false,
    "dynamic_lookup_fallback" : false,
    "new_app_naming" : "APPNAME (kpkg)",
    "self_service_category" : "Apps",
    "test_self_service_category" : "Utilities"
  }
}
```

### package_map.json

#### Example Package Map
```json
{
  "sh.brew.homebrew": {
    "prod_name": "Homebrew",
    "test_name": "Homebrew (Beta Testers)",
    "ss_category": "Productivity",
    "test_category": "Utilities"
  },
  "com.amazon.aws.cli2": {
    "test_name": "Amazon AWS CLI (Devs)"
  },
  "com.cisco.pkg.anyconnect.vpn": {
    "prod_name": "Cisco AnyConnect",
    "test_name": "AnyConnect (Soak Test)"
  },
  "com.microsoft.wdav": {
    "prod_name": "Defender",
    "test_name": "Defender (Soak Test)"
  },
  "com.microsoft.word": {
    "prod_name": "Word",
    "test_name": "Word (Beta Channel)",
    "ss_category": "Apps",
    "test_category": "Apps"
  },
  "org.mozilla.firefox": {
    "prod_name": "Firefox (Browser)",
    "ss_category": "Productivity"
  }
}
```

### kpkg Flags
`kpkg` must be called with one of `-p`/`-b` to specify local PKG/DMG or Homebrew cask name.

`-p`/`-b` may be passed multiple times, so long as no name/category flags are also passed.

See below for full usage guide:

```
usage: kpkg [-h] [-p PKG/DMG] [-b CASK NAME] [-n NAME] [-t TESTNAME] [-s SSCATEGORY] [-z ZZCATEGORY] [-c] [-d] [-y]

Kandji Packages: standalone tool for programmatic management of Kandji Custom Apps

options:
  -h, --help            show this help message and exit
  -p PKG/DMG, --pkg PKG/DMG
                        Path to PKG/DMG for Kandji upload; multiple items can be specified so long as no name/category flags (-n/-t/-s/-z) are passed
  -b CASK NAME, --brew CASK NAME
                        Homebrew cask name which sources PKG/DMG; multiple items can be specified so long as no name/category flags (-n/-t/-s/-z) are passed
  -n NAME, --name NAME  Name of Kandji Custom App to create/update
  -t TESTNAME, --testname TESTNAME
                        Name of Kandji Custom App (test) to create/update
  -s SSCATEGORY, --sscategory SSCATEGORY
                        Kandji Self Service category aligned with --name
  -z ZZCATEGORY, --zzcategory ZZCATEGORY
                        Kandji Self Service category aligned with --testname
  -c, --create          Creates a new Custom App, even if duplicate entry (by name) already exists
  -d, --debug           Sets logging level to debug with maximum verbosity
  -y, --dry             Sets dry run, returning (not executing) changes to stdout as they would have been made in Kandji
```

### kpkg-setup Flags

`kpkg-setup` will run through initial setup to populate required variables if invoked without flags.

See below for full usage guide:

```
Usage: kpkg-setup [-h/--help|-c/--config|-i/--idfind|-m/--map|-r/--reset]

Conducts prechecks to ensure all required dependencies are available prior to runtime.
Once confirmed, reads and prompts to populate values in config.json if any are invalid.

Options:
-h, --help                       Show this help message and exit
-c, --config                     Configure config.json with required values for runtime (don't store secrets)
-i, --idfind                     Populate to CSV names and ids of provided installer media (accepts .pkg/dmg or dir of .pkgs/dmgs)
-m, --map                        Populate to CSV usable values for package_map.json
-r, --reset                      Prompts to overwrite any configurable variables
```

### Audit Enforcement Examples

> #### App not found
> #### ![#E01E5A](https://via.placeholder.com/15/E01E5A/000000?text=+) Fails audit/triggers install
```
Last Audit - 04/15/2024 at 1:51:31 PM
• Executing audit script...
• Script exited with non-zero status.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' not found. Triggering install...
```

> #### App found, version enforcement pending
> #### ![#2EB67D](https://via.placeholder.com/15/2EB67D/000000?text=+) Passes audit/skips install
```
Last Audit - 04/15/2024 at 2:02:34 PM
• Executing audit script...
• Script exited with success.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Update is due at 2024-04-20 11:49:30 PDT
• Will verify 'Google Drive.app' running at least version '90.0' in 4 days, 23 hours, 46 minutes, 57 seconds
```

> #### App found, version enforcement due
> #### Installed version newer/equal to enforced
> #### ![#2EB67D](https://via.placeholder.com/15/2EB67D/000000?text=+) Passes audit/skips install
```
Last Audit - 04/15/2024 at 2:03:21 PM
• Executing audit script...
• Script exited with success.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Enforcement was due at 2024-04-15 11:49:30 PDT
• Confirming 'Google Drive.app' version...
• Installed version '90.0' greater than or equal to enforced version '90.0'
```

> #### App found, version enforcement due
> #### Installed version older than required
> #### User requests one hour delay
> #### ![#2EB67D](https://via.placeholder.com/15/2EB67D/000000?text=+) Passes audit/skips install
```
Last Audit - 04/15/2024 at 2:04:41 PM
• Executing audit script...
• Script exited with success.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Enforcement was due at 2024-04-15 11:49:30 PDT
• Confirming 'Google Drive.app' version...
• Installed version '89.0' less than required version '90.0'
• Detected blocking process: 'Google Drive'
• No enforcement delay found for Google Drive.app
• User clicked Delay
• Writing enforcement delay for Google Drive.app to /Library/Preferences/io.kandji.enforcement.delay.plist
```

> #### App found, version enforcement due
> #### Installed version older than required
> #### User delay still active
> #### ![#2EB67D](https://via.placeholder.com/15/2EB67D/000000?text=+) Passes audit/skips install
```
Last Audit - 04/15/2024 at 2:05:20 PM
• Executing audit script...
• Script exited with success.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Enforcement was due at 2024-04-15 11:49:30 PDT
• Confirming 'Google Drive.app' version...
• Installed version '89.0' less than required version '90.0'
• Detected blocking process: 'Google Drive'
• Enforcement delay present for Google Drive.app
• User delay still pending; enforcing version 90.0 for Google Drive.app in 0 hours, 58 minutes, 59 seconds
```
> #### App found, version enforcement due
> #### Installed version older than required
> #### App is closed (regardless of user delay)
> #### ![#E01E5A](https://via.placeholder.com/15/E01E5A/000000?text=+) Fails audit/triggers install
```
Last Audit - 04/15/2024 at 2:11:31 PM
• Executing audit script...
• Script exited with non-zero status.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Enforcement was due at 2024-04-15 11:49:30 PDT
• Confirming 'Google Drive.app' version...
• Installed version '89.0' less than required version '90.0'
• No running process found for 'Google Drive.app'
• Upgrading 'Google Drive.app' to version '90.0'...
```
> #### App found, version enforcement due
> #### Installed version older than required
> #### User delay has expired
> #### ![#E01E5A](https://via.placeholder.com/15/E01E5A/000000?text=+) Fails audit/triggers install
```
Last Audit - 04/15/2024 at 2:18:05 PM
• Executing audit script...
• Script exited with non-zero status.
• Script results:
• Checking for 'Google Drive.app' install...
• 'Google Drive.app' installed at '/Applications/Google Drive.app'
• Checking version enforcement...
• Enforcement was due at 2024-04-15 11:49:30 PDT
• Confirming 'Google Drive.app' version...
• Installed version '89.0' less than required version '90.0'
• Detected blocking process: 'Google Drive'
• Enforcement delay present for Google Drive.app
• Enforcement delay has expired for Google Drive.app 90.0
• User clicked Quit
• Upgrading 'Google Drive.app' to version '90.0'...
```
