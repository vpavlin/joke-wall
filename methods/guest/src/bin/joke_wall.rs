#![no_main]

use spel_framework::prelude::*;
use joke_wall_core::JokeEntry;

risc0_zkvm::guest::entry!(main);

/// Per-session on-chain state. `#[account_type]` registers it in the IDL so
/// `spel inspect <session-pda> --type SessionState` decodes the bytes to JSON.
/// Must live at file level, not inside `mod joke_wall`.
#[account_type]
#[derive(Debug, Clone, Default, BorshSerialize, BorshDeserialize)]
pub struct SessionState {
    pub admin: [u8; 32],
    pub description: String,
    pub is_active: bool,
    pub jokes: Vec<JokeEntry>,
}

#[lez_program]
mod joke_wall {
    #[allow(unused_imports)]
    use super::*;

    /// Admin creates a new joke-voting session.
    #[instruction]
    pub fn create_session(
        #[account(init, pda = [literal("session_v1"), account("admin")])]
        mut session: AccountWithMetadata,
        #[account(signer)]
        admin: AccountWithMetadata,
        description: String,
    ) -> SpelResult {
        let initial = SessionState {
            admin: *admin.account_id.value(),
            description,
            is_active: true,
            jokes: Vec::new(),
        };
        let bytes = borsh::to_vec(&initial).map_err(|e| SpelError::SerializationError {
            message: e.to_string(),
        })?;
        session.account.data = bytes.try_into().unwrap();
        Ok(SpelOutput::execute(vec![session, admin], vec![]))
    }

    /// Anyone can submit a joke while the session is open.
    /// Each call appends a new JokeEntry to SessionState.jokes.
    #[instruction]
    pub fn submit_joke(
        #[account(mut, pda = [literal("session_v1"), account("admin")])]
        mut session: AccountWithMetadata,
        #[account(signer)]
        submitter: AccountWithMetadata,
        admin: AccountWithMetadata,
        content: String,
    ) -> SpelResult {
        let data: Vec<u8> = session.account.data.clone().into();
        let mut state: SessionState =
            borsh::from_slice(&data).map_err(|e| SpelError::DeserializationError {
                account_index: 0,
                message: e.to_string(),
            })?;

        if !state.is_active {
            return Err(SpelError::Unauthorized {
                message: "Session is closed — no more submissions".to_string(),
            });
        }

        state.jokes.push(JokeEntry {
            submitter: *submitter.account_id.value(),
            content,
            vote_count: 0,
        });

        let bytes = borsh::to_vec(&state).map_err(|e| SpelError::SerializationError {
            message: e.to_string(),
        })?;
        session.account.data = bytes.try_into().unwrap();
        Ok(SpelOutput::execute(vec![session, submitter, admin], vec![]))
    }

    /// Cast a vote for a joke identified by its index in the jokes list.
    #[instruction]
    pub fn vote(
        #[account(mut, pda = [literal("session_v1"), account("admin")])]
        mut session: AccountWithMetadata,
        #[account(signer)]
        voter: AccountWithMetadata,
        admin: AccountWithMetadata,
        joke_index: u64,
    ) -> SpelResult {
        let data: Vec<u8> = session.account.data.clone().into();
        let mut state: SessionState =
            borsh::from_slice(&data).map_err(|e| SpelError::DeserializationError {
                account_index: 0,
                message: e.to_string(),
            })?;

        if !state.is_active {
            return Err(SpelError::Unauthorized {
                message: "Session is closed — voting has ended".to_string(),
            });
        }

        let idx = joke_index as usize;
        if idx >= state.jokes.len() {
            return Err(SpelError::Unauthorized {
                message: format!(
                    "Joke index {} out of range (session has {} jokes)",
                    idx,
                    state.jokes.len()
                ),
            });
        }

        state.jokes[idx].vote_count = state.jokes[idx].vote_count.saturating_add(1);

        let bytes = borsh::to_vec(&state).map_err(|e| SpelError::SerializationError {
            message: e.to_string(),
        })?;
        session.account.data = bytes.try_into().unwrap();
        Ok(SpelOutput::execute(vec![session, voter, admin], vec![]))
    }

    /// Admin closes the session — no further submissions or votes accepted.
    #[instruction]
    pub fn close_session(
        #[account(mut, pda = [literal("session_v1"), account("admin")])]
        mut session: AccountWithMetadata,
        #[account(signer)]
        admin: AccountWithMetadata,
    ) -> SpelResult {
        let data: Vec<u8> = session.account.data.clone().into();
        let mut state: SessionState =
            borsh::from_slice(&data).map_err(|e| SpelError::DeserializationError {
                account_index: 0,
                message: e.to_string(),
            })?;

        if admin.account_id.value() != &state.admin {
            return Err(SpelError::Unauthorized {
                message: "Only the admin can close the session".to_string(),
            });
        }

        state.is_active = false;

        let bytes = borsh::to_vec(&state).map_err(|e| SpelError::SerializationError {
            message: e.to_string(),
        })?;
        session.account.data = bytes.try_into().unwrap();
        Ok(SpelOutput::execute(vec![session, admin], vec![]))
    }

    /// Read-only: returns the session account unchanged for `spel inspect`.
    #[instruction]
    pub fn reveal(
        #[account(pda = [literal("session_v1"), account("admin")])]
        session: AccountWithMetadata,
        admin: AccountWithMetadata,
    ) -> SpelResult {
        Ok(SpelOutput::execute(vec![session, admin], vec![]))
    }
}
