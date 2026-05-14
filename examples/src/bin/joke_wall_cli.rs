//! joke-wall CLI — wraps `spel` for common operations.
//!
//! Usage: joke_wall_cli <command> [options]
//!
//! Commands:
//!   create_session  --description <text>
//!   submit_joke     --content <text>
//!   vote            --joke_index <N>
//!   close_session
//!   reveal
//!   inspect         <binary_path>

use std::env;
use std::process::{Command, exit};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: joke_wall_cli <command> [args...]");
        eprintln!("       joke_wall_cli inspect <binary_path>");
        eprintln!("");
        eprintln!("Commands: create_session, submit_joke, vote, close_session, reveal, inspect");
        exit(1);
    }

    match args[1].as_str() {
        "inspect" => {
            if args.len() < 3 {
                eprintln!("Usage: joke_wall_cli inspect <binary_path>");
                exit(1);
            }
            inspect_binary(&args[2]);
        }
        cmd => {
            // Delegate everything else to `spel` using the IDL in spel.toml
            let status = Command::new("spel")
                .arg(cmd)
                .args(&args[2..])
                .status()
                .unwrap_or_else(|e| {
                    eprintln!("Failed to run spel: {}", e);
                    exit(1);
                });
            exit(status.code().unwrap_or(1));
        }
    }
}

fn inspect_binary(path: &str) {
    use std::fs;
    let bytes = fs::read(path).unwrap_or_else(|e| {
        eprintln!("Cannot read binary '{}': {}", path, e);
        exit(1);
    });
    // RISC Zero ELF ImageID is the SHA-256 of the ELF, formatted as 8 u32 LE words in hex.
    // `wallet deploy-program` prints it; here we just show the file size as a sanity check.
    println!("Binary: {}", path);
    println!("Size:   {} bytes", bytes.len());
    println!("Use 'wallet deploy-program {}' to deploy and get the program ID.", path);
}
