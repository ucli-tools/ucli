<h1> ucli: Universal Command Line Interface Tool </h1>

<h2>Table of Contents</h2>

- [Introduction](#introduction)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Interactive Mode](#interactive-mode)
  - [Command-Line Mode](#command-line-mode)
- [Prerequisites](#prerequisites)
- [Contributing](#contributing)
- [License](#license)

---

## Introduction

`ucli` is a bash script designed for Ubuntu to simplify the process of building tools from GitHub repositories. It provides an interactive menu and command-line interface. It requires `git` to be installed on the system.

## Features

* **Interactive Mode:** A user-friendly menu for easy navigation and tool building.  Allows login, building tools, and logout.
* **Command-Line Mode:** Allows execution of specific commands like installation, login, logout, and building a specific repository.
* **GitHub Integration:** Clones repositories from GitHub (requires a `makefile` in the repository root).  Handles authentication via environment variables.
* **Error Handling:** Includes robust error handling and informative messages.
* **Color-Coded Output:** Uses ANSI color codes for improved readability.
* **Temporary Directory Usage:**  Clones repositories into a temporary directory (`/tmp/code/github.com/<org>/<repo>`) and cleans up after build completion or error.


## Installation

To install `ucli`, run the following command:

```bash
wget https://raw.githubusercontent.com/mik-tf/ucli/main/ucli.sh
bash ./ucli.sh install
rm ./ucli.sh
```

This will copy the script to `/usr/local/bin`, make it executable then delete the downloaded files. You can then run it from anywhere in your system.

## Usage

### Interactive Mode

Run `ucli` without any arguments to enter the interactive mode. You will be presented with a menu to login, build a tool, logout, or exit.


### Command-Line Mode

`ucli` supports several command-line options:

* `ucli install`: Installs `ucli` to `/usr/local/bin`.
* `ucli uninstall`: Uninstalls `ucli` from `/usr/local/bin`.
* `ucli login`: Logs in to your GitHub organization, storing the organization name in the `ORG` environment variable.
* `ucli logout`: Logs out of your GitHub organization, removing the `ORG` environment variable.
* `ucli list`: List the public repos of the organization.
* `ucli help`: Shows the help function.
* `ucli build <repo_name>`: Clones the specified repository (e.g., `my-org/my-tool`), runs `make`, and cleans up. Requires being logged in first (`ucli login`). Can take many repos at once.


**Example:** To build a tool from the repository `my-org/my-tool`, you would first log in:

```bash
ucli login
```

Then, build the tool:

```bash
ucli repo my-org/my-tool
```

## Prerequisites

*   `bash` (should be present on most Unix-like systems)
*   `git`
*   `make` (optional)

To download the prerequisites on Debian/Ubuntu systems:

```bash
sudo apt install -y git make
```


## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This work is under the [Apache 2.0 license](./LICENSE).
