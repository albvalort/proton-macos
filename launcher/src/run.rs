//! Launching an installed Windows game through Proton-macOS, with the same environment the
//! Steam client gives a compatibility tool (see docs/research/03-platform-and-launch.md §2.2).

use crate::appinfo::AppInfo;
use crate::compat::Compat;
use crate::steam;
use anyhow::{bail, Context, Result};
use std::io::{IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Where an app may be installed: our library first, then the isolated steamcmd and Steam itself.
pub fn find_install_dir(info: &AppInfo) -> Option<PathBuf> {
    let installdir = info.install_dir()?;
    let roots = [
        steam::library_dir(),
        steam::home().join(".local/share/proton-macos/steamcmd-home/Library/Application Support/Steam/steamapps/common"),
        steam::steam_root().join("steamapps/common"),
    ];
    roots
        .iter()
        .map(|r| r.join(installdir))
        .find(|p| p.is_dir())
}

/// Windows paths in appinfo use backslashes.
fn native(path: &str) -> String {
    path.replace('\\', "/")
}

pub struct Plan {
    pub exe: PathBuf,
    pub args: Vec<String>,
    pub workdir: PathBuf,
}

pub fn plan(info: &AppInfo, dir: &Path, launch_index: usize) -> Result<Plan> {
    let launches = info.windows_launches();
    let launch = launches.get(launch_index).with_context(|| {
        format!(
            "{} has no Windows launch entry #{launch_index} ({} found)",
            info.name(),
            launches.len()
        )
    })?;
    let exe = dir.join(native(&launch.executable));
    if !exe.exists() {
        bail!("{} not found (is the game installed?)", exe.display());
    }
    let workdir = match &launch.workingdir {
        Some(w) if !w.is_empty() => dir.join(native(w)),
        _ => exe.parent().unwrap_or(dir).to_path_buf(),
    };
    let args = launch
        .arguments
        .split_whitespace()
        .map(str::to_string)
        .collect();
    Ok(Plan { exe, args, workdir })
}

pub fn run(
    info: &AppInfo,
    dir: &Path,
    plan: &Plan,
    compat: Option<&Compat>,
    extra_args: &[String],
) -> Result<i32> {
    let proton = steam::proton_tool()?;
    let compatdata = steam::compatdata_dir(info.appid);
    std::fs::create_dir_all(&compatdata)?;

    if !steam::is_steam_running() {
        eprintln!("pmac: warning: Steam is not running; the game will not see the Steam API (achievements, overlay, DRM)");
    }

    let mut cmd = Command::new(proton.join("proton"));
    cmd.arg("waitforexitandrun")
        .arg(&plan.exe)
        .args(&plan.args)
        .args(extra_args);
    cmd.current_dir(&plan.workdir)
        .env("STEAM_COMPAT_DATA_PATH", &compatdata)
        .env(
            "STEAM_COMPAT_CLIENT_INSTALL_PATH",
            steam::steam_client_dir(),
        )
        .env("STEAM_COMPAT_INSTALL_PATH", dir)
        .env("STEAM_COMPAT_APP_ID", info.appid.to_string())
        .env("SteamAppId", info.appid.to_string())
        .env("SteamGameId", info.appid.to_string())
        .env("SteamOverlayGameId", info.appid.to_string());
    if let Some(c) = compat {
        if let Some(backend) = &c.backend {
            if std::env::var_os("PROTON_MAC_GFX").is_none() {
                cmd.env("PROTON_MAC_GFX", backend);
            }
        }
        for (k, v) in &c.env {
            if std::env::var_os(k).is_none() {
                cmd.env(k, v);
            }
        }
    }
    // Steam injects its overlay into what it launches (DYLD_INSERT_LIBRARIES); that is meant for
    // native games and must not reach Wine. PMAC_KEEP_DYLD_INSERT=1 keeps it for experiments.
    let injected = std::env::var("DYLD_INSERT_LIBRARIES").ok();
    if std::env::var_os("PMAC_KEEP_DYLD_INSERT").is_none() {
        cmd.env_remove("DYLD_INSERT_LIBRARIES");
    }

    // Without a terminal (e.g. launched from Steam) nobody sees the output: keep it in a log.
    let log_path = steam::home()
        .join("Library/Logs/proton-macos")
        .join(format!("{}.log", info.appid));
    if !std::io::stderr().is_terminal() {
        std::fs::create_dir_all(log_path.parent().unwrap())?;
        let mut log = std::fs::File::create(&log_path)?;
        writeln!(
            log,
            "pmac run {} ({}) via {}",
            info.appid,
            plan.exe.display(),
            proton.display()
        )?;
        for (k, v) in std::env::vars().filter(|(k, _)| {
            k.starts_with("DYLD_")
                || k.starts_with("Steam")
                || k.starts_with("STEAM_")
                || k == "PATH"
        }) {
            writeln!(log, "env {k}={v}")?;
        }
        writeln!(log, "removed DYLD_INSERT_LIBRARIES: {:?}", injected)?;
        cmd.stdout(log.try_clone()?).stderr(log);
    }
    eprintln!(
        "pmac: running {} ({}) via {}",
        info.name(),
        plan.exe.display(),
        proton.display()
    );
    let status = cmd.status().context("starting proton")?;
    Ok(status.code().unwrap_or(1))
}
