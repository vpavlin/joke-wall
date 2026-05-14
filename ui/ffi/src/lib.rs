//! C FFI for the joke_wall SPEL program.
//!
//! Every exported function accepts a JSON string with at least:
//!   { "wallet_path": "...", "sequencer_url": "...", "program_id_hex": "<64 hex chars>" }
//! Returns: { "success": true, ... } or { "success": false, "error": "..." }
//!
//! Session PDA is derived from the literal seed "session_v1" padded to 32 bytes.
//! The admin AccountId is passed explicitly in each call that needs it.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use borsh::BorshDeserialize;
use joke_wall_core::JokeEntry;
use serde::{Serialize, Deserialize};
use serde_json::{Value, json};
use nssa::{AccountId, ProgramId, PublicTransaction};
use nssa::public_transaction::{Message, WitnessSet};
use sha2::{Sha256, Digest};
use sequencer_service_rpc::RpcClient as _;
use wallet::WalletCore;

// ── SessionState mirror ───────────────────────────────────────────────────────
// Matches the on-chain SessionState field-for-field (borsh order matters).

#[derive(Debug, Clone, BorshDeserialize)]
struct SessionState {
    admin: [u8; 32],
    description: String,
    is_active: bool,
    jokes: Vec<JokeEntry>,
}

// ── Instruction enum ──────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum JokeWallInstruction {
    CreateSession { description: String },
    SubmitJoke { content: String },
    Vote { joke_index: u64 },
    CloseSession,
    Reveal,
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null pointer".into());
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| format!("invalid UTF-8: {}", e))
}

fn to_cstring(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"success":false,"error":"null byte in output"}"#).unwrap())
        .into_raw()
}

fn error_json(msg: &str) -> *mut c_char {
    let v = serde_json::json!(msg).to_string();
    to_cstring(format!("{{\"success\":false,\"error\":{}}}", v))
}

fn parse_program_id_hex(s: &str) -> Result<ProgramId, String> {
    let s = s.trim_start_matches("0x");
    if s.len() != 64 {
        return Err(format!("program_id_hex must be 64 hex chars, got {}", s.len()));
    }
    let bytes = hex::decode(s).map_err(|e| format!("invalid hex: {}", e))?;
    let mut pid = [0u32; 8];
    for (i, chunk) in bytes.chunks(4).enumerate() {
        pid[i] = u32::from_le_bytes(chunk.try_into().unwrap());
    }
    Ok(pid)
}

fn parse_account_id(s: &str) -> Result<AccountId, String> {
    let base58 = s
        .strip_prefix("Public/")
        .or_else(|| s.strip_prefix("Private/"))
        .unwrap_or(s);
    base58.parse().map_err(|_| format!("invalid AccountId: {}", s))
}

fn init_wallet(v: &Value) -> Result<WalletCore, String> {
    if let Some(p) = v["wallet_path"].as_str() {
        std::env::set_var("NSSA_WALLET_HOME_DIR", p);
    }
    if let Some(u) = v["sequencer_url"].as_str() {
        std::env::set_var("NSSA_SEQUENCER_URL", u);
    }
    WalletCore::from_env().map_err(|e| format!("wallet init: {}", e))
}

/// Compute the session PDA.
/// On-chain: `pda = [literal("session_v1"), account("admin")]`
/// spel-framework combines multiple seeds as SHA-256(seed1 || seed2).
fn compute_session_pda(program_id: &ProgramId, admin: &AccountId) -> AccountId {
    let mut literal_seed = [0u8; 32];
    literal_seed[..10].copy_from_slice(b"session_v1");

    let admin_seed: [u8; 32] = *admin.value();

    let mut hasher = Sha256::new();
    hasher.update(literal_seed);
    hasher.update(admin_seed);
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
        let nonces = wallet
            .get_accounts_nonces(signer_ids.clone())
            .await
            .map_err(|e| format!("nonces: {}", e))?;
        let mut signing_keys = Vec::new();
        for sid in &signer_ids {
            let key = wallet
                .storage()
                .user_data
                .get_pub_account_signing_key(*sid)
                .ok_or_else(|| format!("signing key not found for {}", sid))?;
            signing_keys.push(key);
        }
        let message = Message::try_new(program_id, account_ids, nonces, instruction)
            .map_err(|e| format!("message: {:?}", e))?;
        let witness_set = WitnessSet::for_message(&message, &signing_keys);
        let tx = PublicTransaction::new(message, witness_set);
        wallet
            .sequencer_client
            .send_transaction(common::transaction::NSSATransaction::Public(tx))
            .await
            .map_err(|e| format!("submit: {}", e))
            .map(|r| hex::encode(r.0))
    })
}

fn ffi_call(f: impl FnOnce() -> Result<String, String> + std::panic::UnwindSafe) -> *mut c_char {
    match std::panic::catch_unwind(f) {
        Ok(Ok(r))  => to_cstring(r),
        Ok(Err(e)) => error_json(&e),
        Err(e) => {
            let msg = e.downcast_ref::<&str>().map(|s| *s)
                .or_else(|| e.downcast_ref::<String>().map(|s| s.as_str()))
                .unwrap_or("<unknown panic>");
            error_json(&format!("panic: {}", msg))
        }
    }
}

// ── create_session ────────────────────────────────────────────────────────────
// Args: { program_id_hex, wallet_path, sequencer_url, admin, description }

#[no_mangle]
pub extern "C" fn joke_wall_create_session(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || create_session_impl(&args))
}

fn create_session_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet = init_wallet(&v)?;
    let admin = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let description = v["description"].as_str().ok_or("missing description")?.to_string();
    let session = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, admin], vec![admin],
        JokeWallInstruction::CreateSession { description })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

// ── submit_joke ───────────────────────────────────────────────────────────────
// Args: { program_id_hex, wallet_path, sequencer_url, admin, submitter, content }

#[no_mangle]
pub extern "C" fn joke_wall_submit_joke(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || submit_joke_impl(&args))
}

fn submit_joke_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet = init_wallet(&v)?;
    let admin = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let submitter = parse_account_id(v["submitter"].as_str().ok_or("missing submitter")?)?;
    let content = v["content"].as_str().ok_or("missing content")?.to_string();
    let session = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, submitter, admin], vec![submitter],
        JokeWallInstruction::SubmitJoke { content })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

// ── vote ──────────────────────────────────────────────────────────────────────
// Args: { program_id_hex, wallet_path, sequencer_url, admin, voter, joke_index }

#[no_mangle]
pub extern "C" fn joke_wall_vote(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || vote_impl(&args))
}

fn vote_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet = init_wallet(&v)?;
    let admin = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let voter = parse_account_id(v["voter"].as_str().ok_or("missing voter")?)?;
    let joke_index: u64 = v["joke_index"]
        .as_str().and_then(|s| s.parse().ok())
        .or_else(|| v["joke_index"].as_u64())
        .ok_or("missing or invalid joke_index")?;
    let session = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, voter, admin], vec![voter],
        JokeWallInstruction::Vote { joke_index })?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

// ── close_session ─────────────────────────────────────────────────────────────
// Args: { program_id_hex, wallet_path, sequencer_url, admin }

#[no_mangle]
pub extern "C" fn joke_wall_close_session(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || close_session_impl(&args))
}

fn close_session_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet = init_wallet(&v)?;
    let admin = parse_account_id(v["admin"].as_str().ok_or("missing admin")?)?;
    let session = compute_session_pda(&program_id, &admin);
    let tx_hash = submit_tx(&wallet, program_id,
        vec![session, admin], vec![admin],
        JokeWallInstruction::CloseSession)?;
    Ok(json!({"success": true, "tx_hash": tx_hash}).to_string())
}

// ── fetch_state_json ──────────────────────────────────────────────────────────
// Read-only: fetches and decodes SessionState from the sequencer.
// Args: { program_id_hex, wallet_path, sequencer_url }

#[no_mangle]
pub extern "C" fn joke_wall_fetch_state_json(args_json: *const c_char) -> *mut c_char {
    let args = match cstr_to_str(args_json) { Ok(s) => s.to_owned(), Err(e) => return error_json(&e) };
    ffi_call(move || fetch_state_impl(&args))
}

fn fetch_state_impl(args: &str) -> Result<String, String> {
    let v: Value = serde_json::from_str(args).map_err(|e| format!("invalid JSON: {}", e))?;
    let program_id = parse_program_id_hex(v["program_id_hex"].as_str().ok_or("missing program_id_hex")?)?;
    let wallet = init_wallet(&v)?;
    // Accept either a direct session_pda or derive it from admin.
    let session_pda = if let Some(pda) = v["session_pda"].as_str() {
        parse_account_id(pda)?
    } else {
        let admin = parse_account_id(v["admin"].as_str().ok_or("missing session_pda or admin")?)?;
        compute_session_pda(&program_id, &admin)
    };

    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio: {}", e))?;
    let state = rt.block_on(async {
        let account = wallet
            .sequencer_client
            .get_account(session_pda)
            .await
            .map_err(|e| format!("get_account: {}", e))?;
        // An empty account means the session PDA has not been created yet.
        if account.data.is_empty() {
            return Ok(None);
        }
        SessionState::try_from_slice(&account.data)
            .map(Some)
            .map_err(|e| format!("borsh decode: {}", e))
    })?;

    // Session doesn't exist yet — return a clean empty state so the UI shows "no session".
    let Some(state) = state else {
        return Ok(json!({
            "success": true,
            "state": {
                "admin":       "",
                "description": "",
                "is_active":   false,
                "joke_count":  0,
                "jokes":       [],
            }
        }).to_string());
    };

    let jokes: Vec<Value> = state.jokes.iter().enumerate().map(|(i, j)| {
        json!({
            "index":      i,
            "submitter":  hex::encode(j.submitter),
            "content":    j.content,
            "vote_count": j.vote_count,
        })
    }).collect();

    Ok(json!({
        "success": true,
        "state": {
            "admin":       hex::encode(state.admin),
            "description": state.description,
            "is_active":   state.is_active,
            "joke_count":  state.jokes.len(),
            "jokes":       jokes,
        }
    }).to_string())
}

// ── utility ───────────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn joke_wall_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

#[no_mangle]
pub extern "C" fn joke_wall_version() -> *mut c_char {
    to_cstring("0.1.0".to_string())
}
