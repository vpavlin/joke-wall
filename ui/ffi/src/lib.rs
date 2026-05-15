//! Auto-generated C FFI for the joke_wall program (spel-client-gen), with fixes and extensions.
//!
//! Bugs fixed from raw generator output:
//!   - `string` → `String` in instruction enum
//!   - `admin.as_ref()` used before `admin` parsed (reordered)
//!   - `compute_pda` helper didn't include program_id (wrong addresses)
//!   - `init_wallet` missing `sequencer_url`
//!
//! Extensions beyond generated code:
//!   - `joke_wall_fetch_state_json` — read-only state fetch with borsh decode
//!   - `joke_wall_generate_account` — create new HD account via wallet CLI
//!   - `parse_account_id` accepts hex (64 chars) in addition to base58

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use borsh::BorshDeserialize;
use serde::{Serialize, Deserialize};
use serde_json::{Value, json};
use sha2::{Sha256, Digest};
use nssa::{AccountId, ProgramId, PublicTransaction};
use nssa::public_transaction::{Message, WitnessSet};
use sequencer_service_rpc::RpcClient as _;
use wallet::WalletCore;

// ── Borsh types (mirrors on-chain SessionState) ───────────────────────────────

#[derive(Debug, Clone, Default, borsh::BorshSerialize, BorshDeserialize)]
struct JokeEntry {
    pub submitter: [u8; 32],
    pub content: String,
    pub vote_count: u64,
}

#[derive(Debug, Clone, BorshDeserialize)]
struct SessionState {
    admin: [u8; 32],
    description: String,
    is_active: bool,
    jokes: Vec<JokeEntry>,
}

// ── Instruction enum (generated, `string` → `String` fixed) ──────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum JokeWallInstruction {
    CreateSession { description: String },
    SubmitJoke    { content: String },
    Vote          { joke_index: u64 },
    CloseSession,
    Reveal,
}

// ── FFI plumbing (generated) ──────────────────────────────────────────────────

fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() { return Err("null pointer".into()); }
    unsafe { CStr::from_ptr(ptr) }.to_str().map_err(|e| format!("invalid UTF-8: {}", e))
}

fn to_cstring(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"success":false,"error":"null byte"}"#).unwrap())
        .into_raw()
}

fn error_json(msg: &str) -> *mut c_char {
    let v = serde_json::json!(msg).to_string();
    to_cstring(format!("{{\"success\":false,\"error\":{}}}", v))
}

fn ffi_call(f: impl FnOnce() -> Result<String, String> + std::panic::UnwindSafe) -> *mut c_char {
    match std::panic::catch_unwind(f) {
        Ok(Ok(r))  => to_cstring(r),
        Ok(Err(e)) => error_json(&e),
        Err(e) => {
            let msg = e.downcast_ref::<&str>().copied()
                .or_else(|| e.downcast_ref::<String>().map(|s| s.as_str()))
                .unwrap_or("<unknown panic>");
            error_json(&format!("panic: {}", msg))
        }
    }
}

// ── Helpers (generated, with fixes noted) ────────────────────────────────────

fn parse_program_id_hex(s: &str) -> Result<ProgramId, String> {
    let s = s.trim_start_matches("0x");
    if s.len() != 64 { return Err(format!("program_id hex must be 64 chars, got {}", s.len())); }
    let bytes = hex::decode(s).map_err(|e| format!("invalid hex: {}", e))?;
    let mut pid = [0u32; 8];
    for (i, chunk) in bytes.chunks(4).enumerate() {
        pid[i] = u32::from_le_bytes(chunk.try_into().unwrap());
    }
    Ok(pid)
}

/// Accepts base58 (with or without "Public/"/"Private/" prefix) OR 64-char hex bytes.
fn parse_account_id(s: &str) -> Result<AccountId, String> {
    let stripped = s.strip_prefix("Public/").or_else(|| s.strip_prefix("Private/")).unwrap_or(s);
    if let Ok(id) = stripped.parse() { return Ok(id); }
    // Fall back to raw hex bytes (used for admin loaded from session state)
    let hex_s = stripped.trim_start_matches("0x");
    if hex_s.len() == 64 {
        let bytes = hex::decode(hex_s).map_err(|e| format!("invalid hex: {}", e))?;
        let mut arr = [0u8; 32];
        arr.copy_from_slice(&bytes);
        return Ok(AccountId::new(arr));
    }
    Err(format!("invalid AccountId: {}", s))
}

/// Fixed: original generator omitted sequencer_url.
fn init_wallet(v: &Value) -> Result<WalletCore, String> {
    if let Some(p) = v["wallet_path"].as_str()   { std::env::set_var("NSSA_WALLET_HOME_DIR", p); }
    if let Some(u) = v["sequencer_url"].as_str()  { std::env::set_var("NSSA_SEQUENCER_URL", u); }
    WalletCore::from_env().map_err(|e| format!("wallet init: {}", e))
}

/// Fixed: original generator's compute_pda didn't include program_id, producing wrong addresses.
fn compute_session_pda(program_id: &ProgramId, admin: &AccountId) -> AccountId {
    let mut hasher = Sha256::new();
    let mut padded = [0u8; 32];
    padded[..10].copy_from_slice(b"session_v1");
    hasher.update(&padded);
    hasher.update(admin.value());
    let combined: [u8; 32] = hasher.finalize().into();
    let pda_seed = nssa_core::program::PdaSeed::new(combined);
    AccountId::from((program_id, &pda_seed))
}

fn submit_tx(
    wallet: &WalletCore,
    program_id: ProgramId,
    account_ids: Vec<AccountId>,
    signer_ids: Vec<AccountId>,
    instruction: JokeWallInstruction,
) -> Result<String, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {}", e))?;
    rt.block_on(async {
        let nonces = wallet.get_accounts_nonces(signer_ids.clone()).await
            .map_err(|e| format!("nonces: {}", e))?;
        let mut signing_keys = Vec::new();
        for sid in &signer_ids {
            let key = wallet.storage().user_data
                .get_pub_account_signing_key(*sid)
                .ok_or_else(|| format!("signing key not found for {}", sid))?;
            signing_keys.push(key);
        }
        let message = Message::try_new(program_id, account_ids, nonces, instruction)
            .map_err(|e| format!("message: {:?}", e))?;
        let witness_set = WitnessSet::for_message(&message, &signing_keys);
        let tx = PublicTransaction::new(message, witness_set);
        wallet.sequencer_client
            .send_transaction(common::transaction::NSSATransaction::Public(tx))
            .await
            .map_err(|e| format!("submit: {}", e))
            .map(|r| hex::encode(r.0))
    })
}

// ── Generated instruction FFI (bugs fixed, admin parsed before PDA) ───────────

#[no_mangle]
pub extern "C" fn joke_wall_create_session(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_create_session_impl(&args))
}

fn joke_wall_create_session_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id  = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet      = init_wallet(&v)?;
    let admin       = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let description = serde_json::from_value(v["description"].clone()).map_err(|e| format!("parse error: {}", e))?;
    let session     = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, admin], vec![admin],
        JokeWallInstruction::CreateSession { description })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

#[no_mangle]
pub extern "C" fn joke_wall_submit_joke(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_submit_joke_impl(&args))
}

fn joke_wall_submit_joke_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet     = init_wallet(&v)?;
    // Accept admin as base58 ("admin") or as hex bytes from session state ("admin_hex" or "admin")
    let admin_str  = v["admin"].as_str().or_else(|| v["admin_hex"].as_str()).ok_or("missing admin")?;
    let admin      = parse_account_id(admin_str)?;
    let submitter  = parse_account_id(v["submitter"].as_str().ok_or("missing submitter")?)?;
    let content    = serde_json::from_value(v["content"].clone()).map_err(|e| format!("parse error: {}", e))?;
    let session    = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, submitter, admin], vec![submitter],
        JokeWallInstruction::SubmitJoke { content })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

#[no_mangle]
pub extern "C" fn joke_wall_vote(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_vote_impl(&args))
}

fn joke_wall_vote_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet     = init_wallet(&v)?;
    let admin_str  = v["admin"].as_str().or_else(|| v["admin_hex"].as_str()).ok_or("missing admin")?;
    let admin      = parse_account_id(admin_str)?;
    let voter      = parse_account_id(v["voter"].as_str().ok_or("missing voter")?)?;
    let joke_index: u64 = v["joke_index"].as_u64()
        .or_else(|| v["joke_index"].as_str().and_then(|s| s.parse().ok()))
        .ok_or("missing or invalid joke_index")?;
    let session    = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, voter, admin], vec![voter],
        JokeWallInstruction::Vote { joke_index })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

#[no_mangle]
pub extern "C" fn joke_wall_close_session(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_close_session_impl(&args))
}

fn joke_wall_close_session_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet     = init_wallet(&v)?;
    let admin      = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let session    = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, admin], vec![admin],
        JokeWallInstruction::CloseSession)?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

#[no_mangle]
pub extern "C" fn joke_wall_free_string(s: *mut c_char) {
    if !s.is_null() { unsafe { drop(CString::from_raw(s)) }; }
}

#[no_mangle]
pub extern "C" fn joke_wall_version() -> *mut c_char {
    to_cstring("0.1.0".to_string())
}

// ── Extensions (not generated) ────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn joke_wall_fetch_state_json(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_fetch_state_impl(&args))
}

fn joke_wall_fetch_state_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet     = init_wallet(&v)?;
    let session_pda = if let Some(pda) = v["session_pda"].as_str() {
        parse_account_id(pda)?
    } else {
        let admin = parse_account_id(v["admin"].as_str().ok_or("missing session_pda or admin")?)?;
        compute_session_pda(&program_id, &admin)
    };

    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {}", e))?;
    let state = rt.block_on(async {
        let account = wallet.sequencer_client.get_account(session_pda).await
            .map_err(|e| format!("get_account: {}", e))?;
        if account.data.is_empty() { return Ok(None); }
        SessionState::try_from_slice(&account.data)
            .map(Some)
            .map_err(|e| format!("borsh decode: {}", e))
    })?;

    let Some(state) = state else {
        return Ok(json!({"success": true, "state": {
            "admin": "", "admin_hex": "", "description": "",
            "is_active": false, "joke_count": 0, "jokes": [],
        }}).to_string());
    };

    let jokes: Vec<Value> = state.jokes.iter().enumerate().map(|(i, j)| json!({
        "index": i, "submitter": hex::encode(j.submitter),
        "content": j.content, "vote_count": j.vote_count,
    })).collect();

    Ok(json!({"success": true, "state": {
        "admin":       hex::encode(state.admin),
        "admin_hex":   hex::encode(state.admin),
        "description": state.description,
        "is_active":   state.is_active,
        "joke_count":  state.jokes.len(),
        "jokes":       jokes,
    }}).to_string())
}

#[no_mangle]
pub extern "C" fn joke_wall_generate_account(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || joke_wall_generate_account_impl(&args))
}

fn find_wallet_bin() -> Result<String, String> {
    if let Ok(out) = std::process::Command::new("which").arg("wallet").output() {
        if out.status.success() {
            let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !p.is_empty() { return Ok(p); }
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        let p = format!("{}/.cargo/bin/wallet", home);
        if std::path::Path::new(&p).exists() { return Ok(p); }
    }
    Err("wallet binary not found on PATH or ~/.cargo/bin/".into())
}

fn joke_wall_generate_account_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let wallet_bin = find_wallet_bin()?;
    let mut cmd = std::process::Command::new(&wallet_bin);
    cmd.args(["account", "new", "public"]);
    if let Some(p) = v["wallet_path"].as_str() { cmd.env("NSSA_WALLET_HOME_DIR", p); }
    let out = cmd.output().map_err(|e| format!("exec wallet: {}", e))?;
    if !out.status.success() {
        return Err(format!("wallet: {}", String::from_utf8_lossy(&out.stderr)));
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let account_id = stdout.lines()
        .find(|l| l.contains("account_id"))
        .and_then(|l| l.split("Public/").nth(1))
        .and_then(|s| s.split_whitespace().next())
        .map(|s| format!("Public/{}", s))
        .ok_or_else(|| format!("could not parse account ID from wallet output: {}", stdout))?;
    Ok(json!({"success": true, "account_id": account_id}).to_string())
}
