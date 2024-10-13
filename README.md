# remote-ssh-nvim
This plugin is meant to recreate similar behavior to VS Code's Remote SSH plugin by enabling the feel of a local editor while keeping the source code being edited on the remote machine for compilation, execution, etc

## Remote SSH Commands
- `:RemoteSSHCreateConfig` will create a file in the current directory used to specify details of the local-remote session you'd like to run
- `:RemoteSSHStart` sets the plugin to a running state, this must be manually run by the user while in a folder with a .remote-ssh-config.json created and filled
- `:RemoteSSHStop` sets the plugin to an off state

## :RemoteSSHCreateConfig
When this command is called a file is created with the following fields that must be filled by the user:
