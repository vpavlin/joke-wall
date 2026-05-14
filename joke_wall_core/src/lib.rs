use borsh::{BorshDeserialize, BorshSerialize};
use serde::{Deserialize, Serialize};

/// One joke entry stored inside a SessionState.
/// Shared between the on-chain guest program and the off-chain FFI client.
#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize, Serialize, Deserialize)]
pub struct JokeEntry {
    pub submitter: [u8; 32],
    pub content: String,
    pub vote_count: u64,
}
