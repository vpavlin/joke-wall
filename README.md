# joke-wall

A community joke-voting app running on [LEZ](https://logos.co/) (Logos Execution Zone) — a privacy-preserving L2 blockchain powered by RISC Zero zero-knowledge proofs. An admin creates a voting session, participants submit jokes, and anyone can vote for the funniest one. Results are tallied on-chain.

This project was built as a **complete end-to-end example** of the LEZ/SPEL stack: on-chain program, Rust FFI, and a Basecamp UI plugin — including deployment to the public LEZ testnet. If you're exploring SPEL development or wondering how the testnet works, this is meant to be a useful reference.

---

## Table of contents

- [What is LEZ/SPEL?](#what-is-lezspel)
- [Architecture](#architecture)
- [Live testnet session](#live-testnet-session)
- [Basecamp UI plugin](#basecamp-ui-plugin)
- [CLI quickstart](#cli-quickstart)
- [Testnet setup](#testnet-setup)
- [Building from source](#building-from-source)
- [How it works — technical deep dive](#how-it-works--technical-deep-dive)
- [Project structure](#project-structure)
- [Environment variables](#environment-variables)
- [Known limitations](#known-limitations)

---

## What is LEZ/SPEL?

**LEZ** (Logos Execution Zone) is a privacy-preserving L2 blockchain. Programs run inside a RISC Zero zkVM — every transaction is a zero-knowledge proof that the program executed correctly, with private inputs staying private.

**SPEL** (Smart Program Execution Layer) is the framework for writing LEZ programs. A SPEL program is a Rust binary compiled for the `riscv32im-risc0-zkvm-elf` target. It reads accounts, applies logic, and writes back updated state. The sequencer verifies the ZK proof before committing.

Key concepts:
- **Accounts** — addressable storage slots identified by a 32-byte `AccountId` (displayed as base58)
- **PDA** (Program-Derived Address) — an account address deterministically derived from seeds; no private key needed
- **Sequencer** — the node that receives transactions, verifies proofs, and updates state
- **`wallet`** — CLI tool for managing HD-derived accounts and submitting transactions
- **`spel`** — project-specific CLI auto-generated from the program IDL

---

## Architecture

```
joke-wall/
├── methods/guest/src/bin/joke_wall.rs   # On-chain SPEL program (5 instructions)
├── joke_wall_core/src/lib.rs            # Shared types (JokeEntry struct)
├── examples/src/bin/joke_wall_cli.rs    # CLI wrapper around spel
├── ui/
│   ├── ffi/src/lib.rs                   # Rust C FFI for Qt/QML integration
│   ├── src/JokeWallBackend.{h,cpp}      # Qt C++ backend (QObject with Q_PROPERTYs)
│   ├── qml/Main.qml                     # QML UI (sessions sidebar + 4 tabs)
│   └── flake.nix                        # Nix build → portable .lgx package
├── scripts/launch-basecamp.sh           # Launch Basecamp with correct env vars
├── joke-wall-idl.json                   # Program IDL
└── spel.toml                            # IDL + binary for the spel CLI
```

### On-chain state

One `SessionState` account (PDA) per session, derived from `SHA-256("session_v1" || admin_bytes)`:

| Field         | Type             | Description                          |
|---------------|------------------|--------------------------------------|
| `admin`       | `[u8; 32]`       | Session creator's account ID         |
| `description` | `String`         | Human-readable session title         |
| `is_active`   | `bool`           | `false` after `close_session`        |
| `jokes`       | `Vec<JokeEntry>` | All submitted jokes with vote counts |

`JokeEntry`:

| Field        | Type       | Description              |
|--------------|------------|--------------------------|
| `submitter`  | `[u8; 32]` | Submitter's account ID   |
| `content`    | `String`   | The joke text            |
| `vote_count` | `u64`      | Number of votes received |

### Instructions

| Instruction      | Signer    | Description                                   |
|------------------|-----------|-----------------------------------------------|
| `create_session` | admin     | Creates a new session PDA with a description  |
| `submit_joke`    | submitter | Appends a joke to the active session          |
| `vote`           | voter     | Increments `vote_count` for `jokes[index]`   |
| `close_session`  | admin     | Marks session inactive, no more votes/jokes   |
| `reveal`         | —         | Read-only; used with `spel inspect`           |

---

## Live testnet session

There is a live joke-wall session running on the **LEZ testnet**:

- **Sequencer:** `https://testnet.lez.logos.co/`
- **Explorer:** `https://explorer.testnet.lez.logos.co/`
- **Session PDA:** `edECg5HyAC48pc4h1eWX9aVKBehHkdsXkPGEm7SrU4B`
- **Description:** `testnet test`

To watch and interact from the Basecamp UI, add the session PDA in the sidebar. To interact from the CLI, see [Testnet setup](#testnet-setup).

---

## Basecamp UI plugin

The easiest way to use joke-wall is via the [Logos Basecamp](https://github.com/logos-co/logos-basecamp) desktop app.

### Installing the plugin

Download the latest `joke-wall-plugin.lgx` from the [Releases](https://github.com/vpavlin/joke-wall/releases) page, then install it with `lgpm`:

```bash
lgpm --ui-plugins-dir ~/.local/share/Logos/LogosBasecampDev/plugins \
     install --file joke-wall-plugin.lgx
```

Or build from source — see [Building from source](#building-from-source).

### Launching Basecamp

The plugin needs three environment variables. Use the provided script:

```bash
# Point at the testnet (or your own sequencer)
NSSA_WALLET_HOME_DIR=/path/to/wallet \
NSSA_SEQUENCER_URL=https://testnet.lez.logos.co/ \
./scripts/launch-basecamp.sh
```

The script extracts the program ID automatically from the built binary using `spel -p joke_wall inspect`.

Alternatively, set variables manually:

```bash
export NSSA_WALLET_HOME_DIR=/path/to/wallet
export NSSA_SEQUENCER_URL=https://testnet.lez.logos.co/
export JOKE_WALL_PROGRAM_ID_HEX=d709ec8449fd0ec67c82c2f0293d0ec96caf5eb5adf06a2b3aa2b9e7de6d0849
logos-basecamp
```

### Using the plugin

The UI has four tabs and a sessions sidebar:

**Sessions sidebar** — Add any session by PDA address (paste it in the `+` field). You can watch sessions you don't own. Each entry shows a green/grey status dot and the current joke count.

**Accounts tab** — Generate admin, submitter, and voter accounts with one click. Accounts are HD-derived from the wallet and persisted in app settings. You only need to generate them once. To submit jokes to someone else's session, just generate a submitter account — the session's admin is read from on-chain state automatically.

**Jokes tab** — Live leaderboard of jokes sorted by vote count. Click Vote on any joke.

**Submit tab** — Type a joke and submit it to the active session.

**Admin tab** — Create a new session (requires your admin account) or close an existing one.

> **Note:** You can submit jokes and vote on any watched session without being the admin. The plugin reads the session's admin account ID from on-chain state and uses it for PDA derivation — you only need your own submitter/voter account.

---

## CLI quickstart

### Prerequisites

- LEZ/SPEL toolchain installed (provides `wallet` and `spel` binaries)
- A wallet directory (created by `wallet init` or `make setup`)

### 1. Create accounts

```bash
# Create an admin account
wallet account new public
# Output: Public/<base58_id>
export ADMIN_ID=<base58_id>

# Create a voter/submitter account
wallet account new public
export VOTER_ID=<base58_id>
```

### 2. Create a session

```bash
spel create_session --description "My Joke Wall" --admin Public/$ADMIN_ID
```

### 3. Submit jokes

```bash
spel submit_joke \
  --content "Why do programmers prefer dark mode? Because light attracts bugs." \
  --submitter Public/$VOTER_ID \
  --admin Public/$ADMIN_ID

spel submit_joke \
  --content "A SQL query walks into a bar, walks up to two tables and asks... Can I join you?" \
  --submitter Public/$ADMIN_ID \
  --admin Public/$ADMIN_ID
```

### 4. Vote

```bash
spel vote --joke_index 0 --voter Public/$VOTER_ID --admin Public/$ADMIN_ID
spel vote --joke_index 1 --voter Public/$ADMIN_ID --admin Public/$ADMIN_ID
```

### 5. Read state

```bash
# Find your session PDA
spel -p joke_wall inspect methods/guest/target/riscv32im-risc0-zkvm-elf/docker/joke_wall.bin
# → also prints the ProgramId (hex) and the session PDA

# Decode session state
SESSION_PDA=$(...)  # computed from program ID + admin
spel inspect $SESSION_PDA --type SessionState
```

### 6. Close session

```bash
spel close_session --admin Public/$ADMIN_ID
```

---

## Testnet setup

The LEZ testnet is a shared sequencer at `https://testnet.lez.logos.co/`. Transactions are **free** and accounts are auto-initialized on first use — no faucet needed.

### Configure the wallet for testnet

```bash
# Create a dedicated wallet directory
mkdir -p ~/wallets/lez-testnet

# Set the sequencer URL in the wallet config
cat > ~/wallets/lez-testnet/wallet_config.json <<'EOF'
{
  "sequencer_addr": "https://testnet.lez.logos.co/"
}
EOF

# Create accounts
NSSA_WALLET_HOME_DIR=~/wallets/lez-testnet wallet account new public
# → Public/<admin_id>
```

### Deploy the program to testnet

```bash
NSSA_WALLET_HOME_DIR=~/wallets/lez-testnet \
wallet deploy-program methods/guest/target/riscv32im-risc0-zkvm-elf/docker/joke_wall.bin
```

> **Note:** `wallet deploy-program` currently exits silently on success. You can verify deployment by submitting a `create_session` transaction — if it succeeds, the program is deployed. Check `https://explorer.testnet.lez.logos.co/` to find the deployment transaction.

### Get the program ID

```bash
spel -p joke_wall inspect \
  methods/guest/target/riscv32im-risc0-zkvm-elf/docker/joke_wall.bin
# Look for: ImageID (hex bytes): <64 hex chars>
```

This 64-char hex string is `JOKE_WALL_PROGRAM_ID_HEX`. The deployed instance on testnet has:
```
JOKE_WALL_PROGRAM_ID_HEX=d709ec8449fd0ec67c82c2f0293d0ec96caf5eb5adf06a2b3aa2b9e7de6d0849
```

### Run the CLI against testnet

```bash
NSSA_WALLET_HOME_DIR=~/wallets/lez-testnet \
NSSA_SEQUENCER_URL=https://testnet.lez.logos.co/ \
spel create_session --description "Hello testnet" --admin Public/$ADMIN_ID
```

---

## Building from source

### On-chain program

Requires the RISC Zero toolchain:

```bash
cargo risczero build --manifest-path methods/guest/Cargo.toml
# Output: methods/guest/target/riscv32im-risc0-zkvm-elf/docker/joke_wall.bin
```

### FFI + Qt plugin (for local dev)

Requires Qt 6.9+ and CMake:

```bash
# Build the Rust FFI shared library
cd ui/ffi && cargo build --release

# Configure and build the Qt plugin
cd ui
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DFFI_LIB_DIR=ffi/target/release
cmake --build build --parallel

# Install to Basecamp plugins dir
cp build/libjoke_wall_plugin.so \
   ffi/target/release/libjoke_wall_ffi.so \
   ~/.local/share/Logos/LogosBasecampDev/plugins/joke_wall/
```

### Portable .lgx (Nix)

The `.lgx` format is Basecamp's portable plugin package. Building requires Nix with flakes:

```bash
cd ui
nix build .#lgx
# Output: result/joke-wall-plugin.lgx
```

The GitHub Actions [release workflow](.github/workflows/release.yml) builds this automatically on every version tag. Download the latest from [Releases](https://github.com/vpavlin/joke-wall/releases).

---

## How it works — technical deep dive

### On-chain program

The program (`methods/guest/src/bin/joke_wall.rs`) runs inside the RISC Zero zkVM. It uses the `spel_framework` crate which provides `#[lez_program]`, `#[instruction]`, and `#[account(...)]` macros.

The session PDA address is derived as:
```
pda = SHA-256(pad("session_v1", 32) || admin_bytes)
account_id = AccountId::from((program_id, PdaSeed::new(pda)))
```

The `submit_joke` and `vote` instructions accept an `admin` account (not a signer) solely so the sequencer can re-derive and verify the session PDA address. They are signed by the submitter/voter account respectively.

### Rust C FFI

`ui/ffi/src/lib.rs` is compiled as a `cdylib` and exports six C functions. Each accepts a JSON string and returns a JSON string (caller must free with `joke_wall_free_string`). This lets Qt's C++ layer call into Rust via `dlopen`/`dlsym` without a C++ Rust bridge.

> **Note:** The SPEL toolchain includes a code generator, `spel-client-gen`, that can produce this FFI automatically from the IDL JSON. In this project the FFI was written by hand (following the pattern established by [whisper-wall](https://github.com/logos-co/whisper-wall)), but future projects should prefer the generator:
> ```bash
> cargo run -p spel-client-gen -- --idl joke-wall-idl.json --out-dir ui/ffi/src/generated/
> ```
> The generator produces the same JSON-in/JSON-out `extern "C"` pattern plus a typed Rust client and a C header.

The FFI spawns a Tokio runtime per call to handle the async sequencer RPC. Account generation calls the `wallet` binary as a subprocess since the wallet crate doesn't expose a stable Rust API for HD derivation.

A key detail: `submit_joke` and `vote` accept the session admin either as a base58 wallet ID (`"admin"` key) or as raw hex bytes from the session state (`"admin_hex"` key). This allows submitting to watched sessions where the user doesn't own the admin account.

### Qt/QML UI

`JokeWallBackend` (a `QObject`) wraps the FFI calls with Qt's `QtConcurrent::run` for async dispatch and a `QTimer` for 5-second state polling. Properties like `jokes`, `sessions`, and `lastError` are exposed as `Q_PROPERTY` bindings so QML can react to changes.

Account IDs and session PDAs are persisted with `QSettings` — they survive app restarts without needing a separate config file.

The QML root is a `RowLayout` with a 160px session sidebar and a tab panel. The `AccountRow` inline component handles the generate-or-paste pattern for all three account roles.

### Portable packaging with Nix

The `.lgx` file is produced by `nix-bundle-lgx`, a Logos-provided Nix flake that:
1. Builds the Rust FFI crate with a vendored Cargo lock
2. Builds the Qt plugin with CMake
3. Bundles both `.so` files with the QML, manifest, and metadata into a zip archive

The `cargoLock.outputHashes` in `flake.nix` pins every git-sourced dependency so the build is fully reproducible.

---

## Project structure

```
methods/
  guest/
    Cargo.toml                       # riscv32im-risc0-zkvm-elf target
    src/bin/joke_wall.rs             # The on-chain program

joke_wall_core/
  src/lib.rs                         # JokeEntry struct (shared between program + FFI)

examples/
  src/bin/joke_wall_cli.rs           # Thin wrapper: delegates to spel, adds inspect

ui/
  ffi/
    Cargo.toml                       # cdylib crate
    src/lib.rs                       # C FFI exports + Rust logic
  src/
    JokeWallBackend.h / .cpp         # Qt backend
    JokeWallPlugin.h / .cpp          # Basecamp plugin registration
  qml/
    Main.qml                         # UI — sessions sidebar + Jokes/Submit/Admin/Accounts tabs
  flake.nix                          # Nix build → .lgx
  CMakeLists.txt

scripts/
  launch-basecamp.sh                 # Launch helper (extracts program ID automatically)

.github/workflows/
  release.yml                        # Build .lgx on tag push, create GitHub Release

joke-wall-idl.json                   # Program IDL (regenerate with: make idl)
spel.toml                            # spel CLI config (IDL + binary paths)
Makefile                             # make build / idl / deploy / setup / cli ARGS="..."
```

---

## Environment variables

| Variable                   | Default                    | Description                              |
|----------------------------|----------------------------|------------------------------------------|
| `NSSA_WALLET_HOME_DIR`     | `.scaffold/wallet`         | Path to wallet directory                 |
| `NSSA_SEQUENCER_URL`       | `http://127.0.0.1:3040`    | LEZ sequencer RPC endpoint               |
| `JOKE_WALL_PROGRAM_ID_HEX` | *(required)*               | 64-char hex program ID from `spel inspect` |

---

## Known limitations

- **One session per admin** — The session PDA is seeded by the admin account, so each admin address has exactly one session. To run multiple sessions, create multiple admin accounts.
- **All jokes in one account** — All `JokeEntry` records are stored in the single session PDA. This is fine for demos but would hit size limits with hundreds of jokes. A production design would use per-joke PDAs.
- **No double-vote prevention** — The same voter account can vote multiple times. Adding a per-(voter, session) voted-flag PDA would prevent this.
- **`wallet deploy-program` is silent** — The deploy command exits 0 with no output on success. Verify by checking the explorer or submitting a transaction.
