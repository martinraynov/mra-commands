# MRA Commands

Useful commands accessible via terminal using `mra`.

## Installation

Use `make` to see available options.

To install the command:
```
make install
```

Once installed, use it by typing `mra` in your terminal.

To remove the command:
```
make remove
```

## Usage

Run `mra` with no arguments to list all available commands:
```
mra
```

Run a specific command:
```
mra <command> [args...]
```

## Available Commands

### Global

| Command | Description |
|---------|-------------|
| `zsh_reload` | Reload zsh |
| `gprune` | Prune merged git branches |
| `dprune` | Prune docker system (volumes, networks, images) |

### AWS

| Command | Description |
|---------|-------------|
| `compare-api-gateway-envs` | Compare API Gateway configuration between two environments |

## Adding a New Command

1. Create a new `.sh` file in the appropriate folder under `scripts/` (e.g. `scripts/global/` or `scripts/aws/`).
2. Add a `# @description` comment on line 2 — this is used to generate the help listing.
3. The command will be automatically discovered. No changes to `run.sh` needed.

To create a new group, add a new folder under `scripts/`.
