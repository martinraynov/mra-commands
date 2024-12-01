# MRA exec for commands
Usefull commands accessible via terminal using `mra`

## Installation
Use `make` to see available options. 

To install the command run :
```
make install
```
Once installed you can use it by taping `mra` into your terminal

To remove command run : 
```
make remove
```

## Available Commands

The available commands are :
- __list__ : this command will list all available commands in your terminal.
- __zsh_reload__ : this command will reload your ZSH terminal (reset it to take into account new configurations).
- __gprune__ : this command will prune all local git branches on your repo that are merged and deleted on the distant git server.
- __dprune__ : this command will prune all your unused docker components (system, volume, network, images)
