//! Windows depots through DepotDownloader (SteamRE, GPL-2.0), see docs/adr/0005-launcher.md.
//!
//! pmac never sees a password: `login` runs DepotDownloader's QR flow attached to the terminal
//! and DepotDownloader keeps the resulting token (`-remember-password`).

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn depotdownloader() -> Result<PathBuf> {
    let candidates = [
        std::env::var_os("PMAC_DEPOTDOWNLOADER").map(PathBuf::from),
        Some(crate::steam::home().join(".local/opt/depotdownloader/DepotDownloader")),
    ];
    candidates
        .into_iter()
        .flatten()
        .find(|p| p.exists())
        .context("DepotDownloader not found: install it to ~/.local/opt/depotdownloader or set PMAC_DEPOTDOWNLOADER")
}

fn run(cmd: &mut Command) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {cmd:?}"))?;
    if !status.success() {
        bail!("DepotDownloader failed ({status})");
    }
    Ok(())
}

/// Interactive QR login (scan with the Steam mobile app). Fetches the manifest of Spacewar
/// (480, owned by everyone) as the cheapest authenticated request. DepotDownloader refuses
/// `-username` with `-qr`: it takes the account from the QR session and stores the token under
/// that name, which `install` then reuses with `-username <name> -remember-password`.
pub fn login() -> Result<()> {
    let tmp = std::env::temp_dir().join("pmac-login");
    run(Command::new(depotdownloader()?)
        .args(["-qr", "-remember-password"])
        .args(["-app", "480", "-manifest-only", "-dir"])
        .arg(&tmp))
}

/// Downloads the Windows x64 depots of `appid` into `dir`.
pub fn install(appid: u32, username: &str, dir: &Path, validate: bool) -> Result<()> {
    std::fs::create_dir_all(dir)?;
    let mut cmd = Command::new(depotdownloader()?);
    cmd.args([
        "-app",
        &appid.to_string(),
        "-os",
        "windows",
        "-osarch",
        "64",
    ])
    .args(["-username", username, "-remember-password", "-dir"])
    .arg(dir);
    if validate {
        cmd.arg("-validate");
    }
    run(&mut cmd)
}
