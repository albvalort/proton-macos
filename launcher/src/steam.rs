//! Locations and local state of the Steam client and of Proton-macOS.

use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command;

/// SteamID64 of account 0; account id = SteamID64 - this.
const STEAMID64_BASE: u64 = 76561197960265728;

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var("HOME").expect("HOME not set"))
}

pub fn steam_root() -> PathBuf {
    home().join("Library/Application Support/Steam")
}

/// Directory holding the running client's steamclient.dylib (STEAM_COMPAT_CLIENT_INSTALL_PATH).
pub fn steam_client_dir() -> PathBuf {
    steam_root().join("Steam.AppBundle/Steam/Contents/MacOS")
}

/// Proton-macOS data: our own library, prefixes and settings, kept apart from Steam's.
pub fn data_dir() -> PathBuf {
    std::env::var_os("PMAC_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join("Library/Application Support/proton-macos"))
}

pub fn library_dir() -> PathBuf {
    data_dir().join("steamapps/common")
}

pub fn compatdata_dir(appid: u32) -> PathBuf {
    data_dir().join("compatdata").join(appid.to_string())
}

/// The Proton-macOS compatibility tool (dist/proton-macos, as installed by scripts/package.sh).
pub fn proton_tool() -> Result<PathBuf> {
    let candidates = [
        std::env::var_os("PMAC_PROTON").map(PathBuf::from),
        Some(steam_root().join("compatibilitytools.d/proton_macos")),
    ];
    candidates
        .into_iter()
        .flatten()
        .find(|p| p.join("proton").exists())
        .context("Proton-macOS not found: run scripts/package.sh --install or set PMAC_PROTON")
}

pub fn is_steam_running() -> bool {
    Command::new("pgrep")
        .args(["-q", "steam_osx"])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// The most recent account from loginusers.vdf: (account name, SteamID64).
pub fn current_user() -> Result<(String, u64)> {
    let path = steam_root().join("config/loginusers.vdf");
    let text =
        std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
    let mut users = Vec::new();
    let (mut id, mut name, mut recent) = (None, None, false);
    for line in text.lines().map(str::trim) {
        let fields: Vec<&str> = line.split('"').filter(|s| !s.trim().is_empty()).collect();
        match fields.as_slice() {
            [key] if key.len() == 17 && key.chars().all(|c| c.is_ascii_digit()) => {
                if let (Some(i), Some(n)) = (id.take(), name.take()) {
                    users.push((n, i, recent));
                }
                id = key.parse().ok();
                recent = false;
            }
            [key, value] if key.eq_ignore_ascii_case("AccountName") => {
                name = Some(value.to_string())
            }
            [key, value] if key.eq_ignore_ascii_case("MostRecent") => recent = *value == "1",
            _ => {}
        }
    }
    if let (Some(i), Some(n)) = (id, name) {
        users.push((n, i, recent));
    }
    users
        .iter()
        .find(|u| u.2)
        .or_else(|| users.first())
        .map(|(n, i, _)| (n.clone(), *i))
        .context("no Steam account found in loginusers.vdf (log into Steam once)")
}

pub fn account_id(steamid64: u64) -> u32 {
    (steamid64 - STEAMID64_BASE) as u32
}

pub fn userdata_config(steamid64: u64) -> PathBuf {
    steam_root()
        .join("userdata")
        .join(account_id(steamid64).to_string())
        .join("config")
}

/// Apps in the user's library, as cached by the Steam client for its library view.
pub fn library_appids() -> Result<Vec<u32>> {
    let dir = steam_root().join("appcache/librarycache");
    let mut ids: Vec<u32> = std::fs::read_dir(&dir)
        .with_context(|| format!("reading {} (open Steam's library once)", dir.display()))?
        .filter_map(|e| e.ok()?.file_name().to_str()?.parse().ok())
        .collect();
    ids.sort_unstable();
    Ok(ids)
}

pub fn library_art_dir(appid: u32) -> PathBuf {
    steam_root()
        .join("appcache/librarycache")
        .join(appid.to_string())
}

pub fn appinfo_path() -> PathBuf {
    steam_root().join("appcache/appinfo.vdf")
}
